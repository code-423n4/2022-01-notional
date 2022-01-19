// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin-0.7/contracts/math/SafeMath.sol";
import "@openzeppelin-0.7/contracts/token/ERC20/SafeERC20.sol";
import "./ActionGuards.sol";
import "./math/SafeInt256.sol";
import "./stubs/BalanceHandler.sol";
import "./stubs/TokenHandler.sol";
import "./global/StorageLayoutV2.sol";
import "./global/Constants.sol";
import "interfaces/notional/NotionalTreasury.sol";
import "interfaces/compound/ComptrollerInterface.sol";
import "interfaces/compound/CErc20Interface.sol";
import {WETH9_07 as WETH9} from "interfaces/WETH9_07.sol";

contract TreasuryAction is StorageLayoutV2, ActionGuards, NotionalTreasury {
    using SafeMath for uint256;
    using SafeInt256 for int256;
    using SafeERC20 for IERC20;
    using TokenHandler for Token;

    IERC20 public immutable COMP;
    Comptroller public immutable COMPTROLLER;
    WETH9 public immutable WETH;

    /// @dev Emitted when treasury manager is updated
    event TreasuryManagerChanged(address indexed previousManager, address indexed newManager);
    /// @dev Emitted when reserve buffer value is updated
    event ReserveBufferUpdated(uint16 currencyId, uint256 bufferPercentage);

    /// @dev Throws if called by any account other than the owner.
    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /// @dev Harvest methods are only callable by the authorized treasury manager contract
    modifier onlyManagerContract() {
        require(treasuryManagerContract == msg.sender, "Caller is not the treasury manager");
        _;
    }

    /// @dev Checks if the currency ID is valid
    function _checkValidCurrency(uint16 currencyId) internal view {
        require(0 < currencyId && currencyId <= maxCurrencyId, "Invalid currency id");
    }

    constructor(Comptroller _comptroller, WETH9 _weth) {
        COMPTROLLER = _comptroller;
        COMP = IERC20(_comptroller.getCompAddress());
        WETH = _weth;
    }

    /// @notice Sets the new treasury manager contract
    function setTreasuryManager(address manager) external override onlyOwner {
        emit TreasuryManagerChanged(treasuryManagerContract, manager);
        treasuryManagerContract = manager;
    }

    /// @notice Sets the reserve buffer. This is the percentage of the total token balance of an asset token
    /// denominated in 1e8 (where 1e8 equals 100%). The reserve cannot be harvested below this percentage of the
    /// total token balance on the contract. This portion of the reserve will remain on the contract to act as
    /// a buffer against potential insolvency.
    /// @dev A better metric for the reserve buffer would be a percentage of outstanding debts but Notional does
    /// not currently track that number on chain so we will use the token balance (TVL) as a proxy.
    /// @param currencyId refers to the currency of the reserve
    /// @param bufferPercentage the percentage of the buffer in 1e8 decimal precision, where 1e8 is 100%
    function setReserveBuffer(uint16 currencyId, uint256 bufferPercentage)
        external
        override
        onlyOwner
    {
        _checkValidCurrency(currencyId);
        require(
            bufferPercentage <= uint256(Constants.INTERNAL_TOKEN_PRECISION),
            "T: amount too large"
        );
        reserveBuffer[currencyId] = bufferPercentage;
        emit ReserveBufferUpdated(currencyId, bufferPercentage);
    }

    /// @notice This is used in the case of insolvency. It allows the owner to re-align the reserve with its correct balance.
    /// @param currencyId refers to the currency of the reserve
    /// @param newBalance new reserve balance to set, must be less than the current balance
    function setReserveCashBalance(uint16 currencyId, int256 newBalance)
        external
        override
        onlyOwner
    {
        _checkValidCurrency(currencyId);
        // prettier-ignore
        (int256 reserveBalance, /* */, /* */, /* */) = BalanceHandler.getBalanceStorage(Constants.RESERVE, currencyId);
        require(newBalance < reserveBalance, "cannot increase reserve balance");
        // newBalance cannot be negative and is checked inside BalanceHandler.setReserveCashBalance
        BalanceHandler.setReserveCashBalance(currencyId, newBalance);
    }

    /// @notice Claims COMP incentives earned and transfers to the treasury manager contract.
    /// @param cTokens a list of cTokens to claim incentives for
    /// @return the balance of COMP claimed
    function claimCOMP(address[] calldata cTokens)
        external
        override
        onlyManagerContract
        nonReentrant
        returns (uint256)
    {
        // Check that there is no COMP balance before we claim COMP so that we don't inadvertently transfer
        // something we shouldn't.
        require(COMP.balanceOf(address(this)) == 0);
        COMPTROLLER.claimComp(address(this), cTokens);
        // NOTE: If Notional ever lists COMP as a collateral asset it will be cCOMP instead and it
        // will never hold COMP balances directly. In this case we can always transfer all the COMP
        // off of the contract.
        uint256 balance = COMP.balanceOf(address(this));
        // NOTE: the onlyManagerContract modifier prevents a transfer to address(0) here
        COMP.safeTransfer(treasuryManagerContract, balance);
        // NOTE: TreasuryManager contract will emit a COMPHarvested event
        return balance;
    }

    /// @notice redeems and transfers tokens to the treasury manager contract
    function _redeemAndTransfer(
        uint16 currencyId,
        Token memory asset,
        int256 assetInternalRedeemAmount
    ) private returns (uint256) {
        Token memory underlying = TokenHandler.getUnderlyingToken(currencyId);
        int256 assetExternalRedeemAmount = asset.convertToExternal(assetInternalRedeemAmount);

        // This is the actual redeemed amount in underlying external precision
        uint256 redeemedExternalUnderlying = asset
            .redeem(underlying, assetExternalRedeemAmount.toUint())
            .toUint();

        // NOTE: cETH redeems to ETH, converting it to WETH
        if (underlying.tokenAddress == address(0)) {
            WETH9(WETH).deposit{value: address(this).balance}();
        }

        address underlyingAddress = underlying.tokenAddress == address(0)
            ? address(WETH)
            : underlying.tokenAddress;
        IERC20(underlyingAddress).safeTransfer(treasuryManagerContract, redeemedExternalUnderlying);

        return redeemedExternalUnderlying;
    }

    /// @notice Transfers some amount of reserve assets to the treasury manager contract to be invested
    /// into the sNOTE pool.
    /// @param currencies an array of currencies to transfer from Notional
    function transferReserveToTreasury(uint16[] calldata currencies)
        external
        override
        onlyManagerContract
        nonReentrant
        returns (uint256[] memory)
    {
        uint256[] memory amountsTransferred = new uint256[](currencies.length);

        for (uint256 i; i < currencies.length; i++) {
            // Prevents duplicate currency IDs
            if (i > 0) require(currencies[i] > currencies[i - 1], "IDs must be sorted");

            uint16 currencyId = currencies[i];

            _checkValidCurrency(currencyId);

            // Reserve buffer amount in INTERNAL_TOKEN_PRECISION
            uint256 bufferInternal = reserveBuffer[currencyId];

            // Reserve requirement not defined
            if (bufferInternal == 0) continue;

            // prettier-ignore
            (int256 reserve, /* */, /* */, /* */) = BalanceHandler.getBalanceStorage(Constants.RESERVE, currencyId);
            Token memory asset = TokenHandler.getAssetToken(currencyId);

            uint256 totalReserveInternal = reserve.toUint();
            int256 totalBalanceExternal = SafeInt256.toInt(
                IERC20(asset.tokenAddress).balanceOf(address(this))
            );
            uint256 totalBalanceInternal = asset.convertToInternal(totalBalanceExternal).toUint();

            // Reserve balance and buffer are both defined in INTERNAL_TOKEN_PRECISION, so the precision in the
            // calculation here is 1e8 * 1e8 / 1e8
            uint256 requiredReserveInternal = totalBalanceInternal.mul(bufferInternal).div(
                uint256(Constants.INTERNAL_TOKEN_PRECISION)
            );

            if (totalReserveInternal > requiredReserveInternal) {
                int256 assetInternalRedeemAmount = SafeInt256.toInt(
                    totalReserveInternal.sub(requiredReserveInternal)
                );

                // Redeems cTokens and transfer underlying to treasury manager contract
                amountsTransferred[i] = _redeemAndTransfer(
                    currencyId,
                    asset,
                    assetInternalRedeemAmount
                );

                // Updates the reserve balance
                BalanceHandler.harvestExcessReserveBalance(
                    currencyId,
                    reserve,
                    assetInternalRedeemAmount
                );
            }
        }

        // NOTE: TreasuryManager contract will emit an AssetsHarvested event
        return amountsTransferred;
    }
}
