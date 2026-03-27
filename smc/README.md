# smc

## Project structure

-   `contracts` - source code of all the smart contracts of the project and their dependencies.
-   `wrappers` - wrapper classes (implementing `Contract` from ton-core) for the contracts, including any [de]serialization primitives and compilation functions.
-   `tests` - tests for the contracts.
-   `scripts` - scripts used by the project, mainly the deployment scripts.

## How to use

### Build

`npx blueprint build` or `yarn blueprint build`

### Test

`npx blueprint test` or `yarn blueprint test`

### Deploy or run another script

`npx blueprint run` or `yarn blueprint run`

### Add a new contract

`npx blueprint create ContractName` or `yarn blueprint create ContractName`

## Overview: Treasury-based locked dollar

The system mints a **dollar** (one jetton = $1 value) for a user but keeps it **locked in the treasury**. When the app earns liquidity from **paid-in features** (e.g. fees, subscriptions), that liquidity is sent to the **treasury**. Once liquidity is present, the treasury can **release** the dollar fully to the user (transfer from treasury’s jetton wallet to the user’s jetton wallet).

So:

1. **Mint a dollar** → Dollar is minted into the **treasury** (not to the user).
2. **Locked in the treasury** → Treasury holds the jetton and tracks “this dollar belongs to user X” in a ledger.
3. **Liquidity from app** → App’s paid features send TON (or other) to the treasury contract; treasury balance = liquidity.
4. **Add liquidity to the dollar** → Liquidity backs the promise: we only release when there is liquidity (or when admin allows).
5. **Release fully to the user** → Treasury sends the dollar from its jetton wallet to the user’s jetton wallet; user can then use/swap it.

### Design discussion: how the treasury works

- **Who can mint a dollar for a user?**  
  Only the **treasury** (or an admin/minter role). App/backend calls: “mint one dollar for user X.” Treasury asks the **dollar minter** to mint 1 jetton to the **treasury’s jetton wallet**, and the treasury **credits** user X in its ledger (locked balance += 1).

- **Where is the dollar physically?**  
  In the **treasury’s jetton wallet** (one shared wallet for the treasury). The treasury contract does **not** hold jettons; it holds a **ledger**: `map<user_address, locked_amount>`. The sum of all `locked_amount` equals the balance of the treasury jetton wallet (invariant).

- **How does the treasury know “this mint was for user X”?**  
  When the app requests “mint dollar for user X,” the treasury sends a message to the **dollar minter** with “mint 1 to treasury wallet, credited user = X” (e.g. in payload). The minter mints to the **treasury jetton wallet**. The **treasury jetton wallet** is a **custom wallet** that, on receiving jettons (InternalTransfer), notifies the **treasury contract** with “credited user” (from payload) and amount. Treasury then updates its ledger: `lockedForUser[user] += amount`.

- **What is “liquidity”?**  
  TON (or other assets) sent to the **treasury contract** from the app’s paid features. The treasury’s native balance = liquidity. Optionally, release is only allowed when `treasury.getBalance() >= minLiquidityToRelease` (or when admin calls release).

- **How is the dollar released to the user?**  
  Admin (or the contract logic) calls “release dollar to user X.” Treasury checks: `lockedForUser[X] > 0` and (optionally) liquidity is sufficient. Then treasury tells the **treasury jetton wallet**: “transfer `amount` jettons to user X’s jetton wallet.” The treasury jetton wallet is custom: it accepts such **transfer-to-user** orders only from the treasury contract and performs a standard TEP-74 transfer to the user. After that, treasury updates the ledger: `lockedForUser[X] -= amount`.

- **Summary of components**
  - **Treasury contract** — Holds TON (liquidity); ledger `lockedForUser: map<address, uint64>`; receives liquidity, requests mints, receives “credited” from treasury wallet, requests “transfer to user” from treasury wallet.
  - **Jetton contract (dollar minter)** — **Fixed in storage**: `owner`, `treasuryWalletAddress`. Mints only to that treasury jetton wallet (payload = user to credit). Only owner (e.g. treasury) can request mint.
  - **Treasury jetton wallet** — **Amount**: `balance` (coins) — jettons held. **Fixed in storage**: `owner` (treasury), `minter`. **State**: `isLockedByTreasury: bool` — when true, standard Transfer is rejected; only treasury can order “transfer to user”. On InternalTransfer: notify treasury with (user, amount). On “transfer to user” from treasury: perform TEP-74 transfer to that user. (Treasury wallet address is fixed in the **jetton contract** and in the **Treasury** contract.)

All of this is specified in Tolk-friendly form in **[TOLK_SPEC.md](./TOLK_SPEC.md)** (storage structs, message opcodes, entrypoints, flows).

## Architecture (Treasury-based)

```
                    ┌─────────────────────────────────────┐
                    │         Treasury Contract           │
                    │  - TON balance = liquidity          │
                    │  - Ledger: lockedForUser[addr]     │
                    │  - Requests mint / release           │
                    └──────────────┬──────────────────────┘
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         │                         │                         │
         ▼                         ▼                         ▼
┌─────────────────┐    ┌──────────────────────┐    ┌─────────────────────┐
│  App paid       │    │ Treasury Jetton     │    │ Dollar Minter       │
│  features       │    │ Wallet (custom)      │    │ (TEP-74)            │
│  → send TON     │    │ - Holds all locked   │    │ - Mints to treasury │
│  to treasury    │    │   dollars            │    │   wallet only       │
└─────────────────┘    │ - Notifies treasury │    │ - Payload = user    │
                        │   on receive        │    └─────────────────────┘
                        │ - Transfers to user │
                        │   on treasury order │
                        └──────────┬──────────┘
                                   │
                                   │ release: transfer to user
                                   ▼
                        ┌──────────────────────┐
                        │ User's Jetton Wallet │
                        │ (standard TEP-74)    │
                        └──────────────────────┘
```

## Tolk implementation specification

**[TOLK_SPEC.md](./TOLK_SPEC.md)** contains the Tolk-level specification for this treasury system: storage structs, message opcodes, entrypoints (MintDollarForUser, Credited, ReleaseDollarToUser, AddLiquidity), custom treasury wallet behaviour, and createMessage/stateInit usage.

---

## Smart contract components (summary)

| Contract | Role |
|----------|------|
| **Treasury** | Holds TON (liquidity); ledger `lockedForUser[address]`; receives liquidity; requests mint for user; receives “credited” from treasury wallet; requests “transfer to user” from treasury wallet. |
| **Jetton contract (Dollar Minter)** | **Fixed in storage**: `owner`, `treasuryWalletAddress`. TEP-74 minter. Mints only to that treasury jetton wallet (payload = user to credit). Only owner can request mint. |
| **Treasury Jetton Wallet** | **Amount**: `balance` (coins). **Fixed in storage**: `owner`, `minter`. **State**: `isLockedByTreasury` — when true, standard Transfer rejected; only treasury can order transfer to user. On InternalTransfer: notify treasury with (user, amount). On order from treasury: transfer jettons to user. |

Full Tolk-level specs (storage, messages, entrypoints) are in **[TOLK_SPEC.md](./TOLK_SPEC.md)**.

## Implementation Strategy

### Phase 1: Core

1. **Study TEP-74** (Jettons) and Tolk reference implementations; define **opcodes** and **errors** in `contracts/common`.
2. **Project layout**: `contracts/treasury.tolk`, `contracts/treasury-jetton-wallet.tolk`, `contracts/dollar-minter.tolk`, plus `common/opcodes.tolk`, `common/errors.tolk`.

### Phase 2: Treasury + Treasury Jetton Wallet

1. **Treasury**: Storage (ledger `lockedForUser`, minter address, treasury wallet address, admin); handle `MintDollarForUser`, `Credited`, `ReleaseDollarToUser`, `AddLiquidity` (receive TON).
2. **Treasury Jetton Wallet**: Custom TEP-74 wallet; on InternalTransfer notify treasury with credited user from payload; accept “transfer to user” only from treasury.

### Phase 3: Dollar Minter

1. **Dollar Minter**: TEP-74 minter; mint only to treasury jetton wallet with payload = user to credit; only treasury (or authorized) can request mint.

### Phase 4: Integration & Testing

- [ ] End-to-end: mint dollar for user → credited in treasury → add liquidity → release to user.
- [ ] Bounces, unauthorized calls, ledger consistency (sum of locked = treasury wallet balance).

## Technical Considerations

- **Ledger invariant**: Sum of `lockedForUser[*]` = balance of treasury jetton wallet.
- **Credited user**: Passed in mint payload; treasury wallet parses it and notifies treasury so ledger stays correct.
- **Release condition**: Optional: only allow release when treasury TON balance >= `minLiquidityToRelease` (or always allow if admin calls).

## Integration with Frontend

1. **Mint dollar for user**: App calls Treasury `MintDollarForUser(userAddress)`.
2. **Add liquidity**: App’s paid features send TON to the treasury contract (no special message; balance grows).
3. **Locked balance**: Getter `getLockedForUser(userAddress)` (or iterate ledger in wrapper).
4. **Release**: Admin (or app when liquidity is there) calls Treasury `ReleaseDollarToUser(userAddress)`.

## Testing Checklist

- [ ] Unit tests: treasury ledger, treasury wallet notify/transfer, minter mint to treasury only.
- [ ] Integration: full flow mint → credited → release; liquidity check if used; unauthorized access.

## Deployment Plan

1. Deploy Dollar Minter, then Treasury Jetton Wallet (owner = treasury), then Treasury (with minter + treasury wallet addresses).
2. Configure admin; send initial liquidity if using a minimum-balance gate.

## Future Enhancements

- Minimum liquidity threshold before release; batch release; events for indexers.

## References

- [TEP-74: Jettons Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md)
- [Tolk Language Documentation](https://docs.ton.org/v3/documentation/smart-contracts/tolk)
- [TOLK_SPEC.md](./TOLK_SPEC.md) — Tolk-level specification for this treasury system

---

**Status**: 📋 Treasury design — see TOLK_SPEC.md for implementation details  
**Next steps**: Confirm design (who mints, release condition), then implement from TOLK_SPEC.md