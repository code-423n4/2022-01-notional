# Notional contest details

- $71,250 USDC main award pot
- $3,750 USDC gas optimization award pot
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2022-01-notional-contest/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts January 27, 2022 00:00 UTC
- Ends February 2, 2022 23:59 UTC

This repo will be made public before the start of the contest. (C4 delete this line when made public)

# Marketing Details

- [Notional Logos](https://github.com/notional-finance/media-kit/tree/master/Logos)
- Twitter: @NotionalFinance
- Discord: https://discord.notional.finance
- Website: https://notional.finance

# Audit Scope

| Module    | File                | Code | Comments | Total Lines | Complexity / Line |
| :-------- | :------------------ | ---: | -------: | ----------: | ----------------: |
| Contracts | ActionGuards.sol    |   13 |        5 |          24 |               7.7 |
| Contracts | TreasuryAction.sol  |  142 |       45 |         217 |              11.3 |
| Contracts | TreasuryManager.sol |  122 |        4 |         146 |               3.3 |
| Contracts | sNOTE.sol           |  234 |       88 |         386 |               4.3 |
| Global    | Constants.sol       |    8 |        7 |          19 |               0.0 |
| Global    | LibStorage.sol      |   47 |       17 |          71 |               0.0 |
| Global    | StorageLayoutV1.sol |   19 |       28 |          54 |               0.0 |
| Global    | StorageLayoutV2.sol |    8 |        4 |          16 |               0.0 |
| Global    | Types.sol           |   23 |       23 |          50 |               0.0 |
| Math      | Bitmap.sol          |   69 |       13 |          91 |              23.2 |
| Math      | FloatingPoint56.sol |   14 |       14 |          34 |               7.1 |
| Math      | SafeInt256.sol      |   46 |       15 |          83 |              34.8 |
| Stubs     | BalanceHandler.sol  |   57 |       12 |          81 |               5.3 |
| Stubs     | TokenHandler.sol    |   63 |       19 |          95 |              25.4 |
| Utils     | BoringOwnable.sol   |   33 |       16 |          58 |              18.2 |
| Utils     | EIP1271Wallet.sol   |   38 |        4 |          46 |              10.5 |
| Utils     | EmptyProxy.sol      |   11 |        3 |          18 |               9.1 |
| Utils     | nProxy.sol          |   13 |        2 |          19 |               0.0 |

# Staked NOTE Specification

The goal of Staked NOTE is to align NOTE token holders with the long term success of the Notional protocol. NOTE holders can stake their NOTE to earn additional yield while signalling that they are willing to provide valuable liquidity over the long term. It's design is inspired by the Aave Safety Module (stkAAVE). Over time we hope to achieve:

- Reduced NOTE circulating supply
- On Chain liquidity for trading NOTE
- NOTE token holders can share in the success of the protocol

There are two primary components of the Staked NOTE design:

- [Staked NOTE (sNOTE)](#staked-note): NOTE tokens used to provide liquidity for NOTE/ETH trading (in an 80/20 Balancer Pool) as well as acting as a backstop for Notional in the event of a [collateral shortfall event](#collateral-shortfall-event).
- [Treasury Manager](#treasury-management): an account appointed by NOTE governors to carry out specific Notional treasury management functions.

## Staked NOTE

### Minting sNOTE

Staked NOTE (sNOTE) is minted to NOTE token holders in return for either NOTE or underlying sNOTE Balancer Pool Tokens (BPT). If only NOTE is supplied then some will be sold as ETH to mint the corresponding amount of BPT. All NOTE staked in sNOTE is used to provide liquidity in an 80/20 NOTE/ETH Balancer Pool. The 80/20 ratio reduces the impact of impermanent loss to sNOTE holders while they earn trading fees on NOTE/ETH.

### Redeeming sNOTE

sNOTE is also used as a backstop during a [collateral shortfall event](#collateral-shortfall-event). When this is triggered via governance, 30% of underlying sNOTE BPT will be transferred to the [Treasury Manager](#treasury-manager) to be sold to recover the collateral shortfall. Therefore, to prevent sNOTE holders from front running a collateral shortfall event the sNOTE contract will enforce a cool down period before sNOTE redemptions can occur. sNOTE holders can only redeem sNOTE to underlying BPT during their redemption window.

### Collateral Shortfall Event

In the event of a hack or account insolvencies, the Notional protocol may not have sufficient collateral to pay lenders their principal plus interest. In this event, NOTE governors will declare a collateral shortfall event and withdraw up to 30% of the sNOTE BPT tokens into NOTE and ETH. The NOTE portion will be sold or auctioned in order to generate collateral to repay lenders.

### sNOTE Yield Sources

sNOTE will earn yield from:

- Notional treasury management will periodically trade Notional protocol profits into ETH in order to purchase NOTE and increase the overall BPT share that sNOTE holders have a claim on.
- Governance may decide to incentivize sNOTE with additional NOTE tokens for some initial bootstrapping period.
- Trading fees on the Balancer Pool. Since we anticipate that the sNOTE BPT pool will the the deepest liquidity for NOTE on chain, most NOTE DEX trading will likely come through this pool. sNOTE holders will be able to set the trading fee on the pool.

### sNOTE Voting Power

sNOTE holders will also be able to vote in Notional governance just like NOTE holders. The voting power of an sNOTE token is based on the amount of underlying NOTE the Balancer pool tokens have a claim on, using Balancer's provided price oracles.

Because the price oracle will be a lagged weighted average, the sNOTE voting power will likely be slightly higher or lower than the spot claim on Balancer pool tokens.
