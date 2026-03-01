# Tolk Implementation Specification — Treasury & Locked Dollar

This document is the **Tolk-level specification** for the [README.md](./README.md) treasury system: mint a dollar into the treasury (locked), add liquidity from the app’s paid features, then release the dollar fully to the user. It uses **Tolk syntax, types, and patterns** so contracts can be implemented directly in `.tolk` files.

---

## 1. Tolk language conventions

### 1.1 Version and imports

- Start every contract with a strict compiler version:
  ```tolk
  tolk 1.0
  ```
- Common project modules:
  ```tolk
  import "opcodes"
  import "errors"
  ```

### 1.2 Naming and style

- **camelCase** for functions, methods, variables, and getter names.
- **Structs**: PascalCase (e.g. `TreasuryStorage`).
- **Constants**: UPPER_SNAKE (e.g. `OP_MINT_DOLLAR_FOR_USER`, `ERROR_UNAUTHORIZED`).

### 1.3 Types

| Concept        | Tolk type(s)              | Notes |
|----------------|---------------------------|--------|
| Balance / amount | `coins`                 | `ton("0.05")` for literals. |
| Address        | `address`, `address?`     | `contract.getAddress()` for self. |
| Ledger (user → amount) | `map<address, uint64>` | Per-user locked dollar balance. |
| Optional ref   | `cell?`, `Cell<T>?`     | For optional payloads. |
| Message tail   | `RemainingBitsAndRefs`    | For “rest of body” when **reading** (not `slice`). |
| Fixed-width int | `uint32`, `uint64`      | For storage and message fields. |

### 1.4 Storage pattern

- **Load**: `fun Storage.load()` returns `Storage.fromCell(contract.getData())`.
- **Save**: method with `mutate self` that calls `contract.setData(self.toCell())`.
- Use **`lazy Storage.load()`** where only some fields are needed.

### 1.5 Message handling

- Parse body with **`lazy`** and **union** + **match**; message structs use **32-bit opcode**: `struct (0x...) Name { ... }`.
- **Getters**: `get fun name(): ReturnType { ... }`.
- **Sender**: `in.senderAddress` (InMessage).
- **createMessage** for all outbound messages; **stateInit** / **toShard** for deployment.

---

## 2. Common definitions

### 2.1 Opcodes (`contracts/common/opcodes.tolk`)

```tolk
tolk 1.0

// Treasury (choose unique 32-bit opcodes)
const OP_MINT_DOLLAR_FOR_USER  = 0x...  // App/Admin → Treasury: mint dollar for user
const OP_CREDITED              = 0x...  // Treasury wallet → Treasury: credited user
const OP_RELEASE_DOLLAR_TO_USER = 0x... // Admin → Treasury: release to user
const OP_ADD_LIQUIDITY         = 0x...  // App → Treasury: add liquidity (no-op, TON attached)
const OP_TRANSFER_TO_USER      = 0x...  // Treasury → Treasury wallet: transfer amount to user
const OP_MINT_TO_TREASURY      = 0x...  // Treasury → Dollar Minter: mint to treasury wallet (creditedUser in body)

// TEP-74 (confirm against standard)
const OP_JETTON_TRANSFER      = 0x0f8a7ea5
const OP_INTERNAL_TRANSFER    = 0x178d4519
```

### 2.2 Error codes (`contracts/common/errors.tolk`)

```tolk
tolk 1.0

const ERROR_UNAUTHORIZED        = 403
const ERROR_INSUFFICIENT        = 404
const ERROR_LIQUIDITY           = 405
const ERROR_LOCKED_BY_TREASURY  = 406
```

---

## 3. Contract 1: Treasury

**Purpose**: Hold TON (liquidity); ledger of locked dollars per user; request mint for user; receive “credited” from treasury wallet; request “transfer to user” from treasury wallet.

### 3.1 Storage

```tolk
struct TreasuryStorage {
    adminAddress: address
    minterAddress: address
    treasuryWalletAddress: address      // Treasury jetton wallet (owner = this contract)
    lockedForUser: map<address, uint64>  // user → locked dollar amount (invariant: sum = treasury wallet balance)
    totalLocked: uint64
    minLiquidityToRelease: coins = ton("0")  // optional: only allow release when treasury balance >= this
}
```

- **Load**: `return TreasuryStorage.fromCell(contract.getData())`.
- **Save**: `contract.setData(self.toCell())` in a method that takes `mutate self`.
- **Invariant**: Sum of `lockedForUser[*]` = balance of treasury jetton wallet; `totalLocked` can mirror that sum for quick checks.

### 3.2 Messages (incoming)

```tolk
struct (OP_MINT_DOLLAR_FOR_USER) MintDollarForUser {
    queryId: uint64
    userAddress: address
}

struct (OP_CREDITED) Credited {
    queryId: uint64
    userAddress: address
    amount: coins
}

struct (OP_RELEASE_DOLLAR_TO_USER) ReleaseDollarToUser {
    queryId: uint64
    userAddress: address
}

// Add liquidity: just receive TON (no body, or empty body with opcode)
struct (OP_ADD_LIQUIDITY) AddLiquidity {
    queryId: uint64
}
```

- **MintDollarForUser**: Only `storage.adminAddress` (or treasury itself). Treasury sends to **Dollar Minter**: mint 1 to treasury jetton wallet with payload = `userAddress`. (Ledger is updated when treasury wallet sends **Credited**.)
- **Credited**: Only from `storage.treasuryWalletAddress`. `lockedForUser[userAddress] += amount`, `totalLocked += amount`; then save.
- **ReleaseDollarToUser**: Only `storage.adminAddress` (or allowed role). Optional: `assert (contract.getBalance() >= storage.minLiquidityToRelease) throw ERROR_LIQUIDITY`. Check `lockedForUser[userAddress] >= amount` (e.g. amount = full locked for that user). Send to **treasury jetton wallet**: **TransferToUser** `(amount, userAddress)`. Then `lockedForUser[userAddress] -= amount`, `totalLocked -= amount`; save.
- **AddLiquidity**: No-op; TON is attached so treasury balance increases. Optionally require a minimal body with opcode so only app can send.

Union:

```tolk
type TreasuryMessage = MintDollarForUser | Credited | ReleaseDollarToUser | AddLiquidity
```

### 3.3 Entrypoint

```tolk
fun onInternalMessage(in: InMessage) {
    val storage = lazy TreasuryStorage.load();
    val msg = lazy TreasuryMessage.fromSlice(in.body);
    match (msg) {
        MintDollarForUser => {
            assert (in.senderAddress == storage.adminAddress) throw ERROR_UNAUTHORIZED;
            // createMessage to Dollar Minter: MintToTreasury(queryId, amount=1 dollar, creditedUser=msg.userAddress)
            // dest = storage.minterAddress; send; ledger updated when Credited received
        }
        Credited => {
            assert (in.senderAddress == storage.treasuryWalletAddress) throw ERROR_UNAUTHORIZED;
            var st = TreasuryStorage.load();
            // r = st.lockedForUser.get(msg.userAddress); if r.isFound then v = r.loadValue() else v = 0;
            // st.lockedForUser.set(msg.userAddress, v + msg.amount); st.totalLocked += msg.amount; st.save()
        }
        ReleaseDollarToUser => {
            assert (in.senderAddress == storage.adminAddress) throw ERROR_UNAUTHORIZED;
            // optional: assert (contract.getBalance() >= storage.minLiquidityToRelease) throw ERROR_LIQUIDITY
            var st = TreasuryStorage.load();
            val r = st.lockedForUser.get(msg.userAddress);
            assert (r.isFound) throw ERROR_INSUFFICIENT;
            val amount = r.loadValue();
            // createMessage to storage.treasuryWalletAddress: TransferToUser(queryId, amount, msg.userAddress)
            // then st.lockedForUser.set(msg.userAddress, 0) or delete; st.totalLocked -= amount; st.save()
        }
        AddLiquidity => { /* no-op; balance already increased */ }
        else => assert (in.body.isEmpty()) throw 0xFFFF
    }
}
```

### 3.4 Getters

```tolk
get fun getTreasuryData(): (admin: address, minter: address, treasuryWallet: address, totalLocked: uint64) {
    val st = lazy TreasuryStorage.load();
    return (st.adminAddress, st.minterAddress, st.treasuryWalletAddress, st.totalLocked);
}

get fun getLockedForUser(userAddress: address): uint64 {
    val st = lazy TreasuryStorage.load();
    val r = st.lockedForUser.get(userAddress);
    return r.isFound ? r.loadValue() : 0;
}
```

(For `getLockedForUser` with argument, if the SDK supports getter args use the above; otherwise implement in wrapper by reading full ledger or a dedicated getter that returns a cell/slice.)

---

## 4. Contract 2: Treasury Jetton Wallet

**Purpose**: Custom TEP-74 jetton wallet. **Owner** and **treasury wallet address** are fixed in storage. **State**: `isLockedByTreasury` — when true, standard Transfer is rejected; only treasury can order TransferToUser. (1) On **InternalTransfer**: notify Treasury with (user from payload, amount). (2) On **TransferToUser** from Treasury only: perform TEP-74 transfer to the given user.

### 4.1 Storage

```tolk
struct TreasuryJettonWalletStorage {
    balance: coins                   // amount of jettons held (TEP-74 balance)
    owner: address                   // Treasury contract address (fixed at deploy)
    minter: address                  // Dollar minter address (fixed at deploy)
    jettonWalletCode: cell           // for standard interface
    isLockedByTreasury: bool = true  // state: when true, standard TEP-74 Transfer rejected; only TransferToUser from owner allowed
}
```

- **Amount**: `balance: coins` — current amount of jettons held by this wallet (increases on InternalTransfer, decreases on TransferToUser / Transfer).
- **Fixed at deploy**: `owner`, `minter` (never changed). Treasury wallet address is fixed in the **jetton contract** and in the **Treasury** contract.
- **State**: `isLockedByTreasury`. When **true**: incoming TEP-74 **Transfer** → throw; only **TransferToUser** from `owner` (treasury) is allowed. When **false**: normal TEP-74 **Transfer** allowed (optional; treasury can set to false to “unlock” the wallet).

### 4.2 Messages (incoming)

- **InternalTransfer** (TEP-74): from minter. Increase balance; parse **forwardPayload** (or customPayload) for **credited user** address; send **Credited(user, amount)** to `owner` (treasury).
- **Transfer** (TEP-74): when **isLockedByTreasury** is true, **reject** (throw). When false, handle as standard TEP-74 transfer.
- **TransferToUser** (custom, treasury only):

  ```tolk
  struct (OP_TRANSFER_TO_USER) TransferToUser {
      queryId: uint64
      amount: coins
      toUserAddress: address
  }
  ```

  Sender must be `storage.owner` (treasury). Decrease balance; send standard TEP-74 **Transfer** to user’s jetton wallet (deploy user wallet if needed via stateInit). Optionally send excesses back to treasury.

- **SetLockedByTreasury** (optional, treasury only): set `isLockedByTreasury` to a new value (only `owner` can call).

Union (example):

```tolk
type TreasuryWalletMessage = InternalTransfer | Transfer | TransferToUser | SetLockedByTreasury
```

### 4.3 InternalTransfer handling

- Load storage; check sender is minter; increase `balance` by `msg.amount`; save.
- Parse `msg.forwardPayload` (or customPayload) to get `address creditedUser` (e.g. slice contains address; use RemainingBitsAndRefs or a small struct with one address).
- **createMessage** to `storage.owner` (treasury): body = **Credited** `{ queryId: msg.queryId, userAddress: creditedUser, amount: msg.amount }`; send.

### 4.4 Transfer handling (TEP-74)

- When **isLockedByTreasury** is **true**: do not process standard Transfer; throw (e.g. ERROR_LOCKED_BY_TREASURY).
- When **false**: process as normal TEP-74 transfer.

### 4.5 TransferToUser handling

- Assert `in.senderAddress == storage.owner`; load storage; assert `storage.balance >= msg.amount`; decrease balance; save.
- **createMessage** to user’s jetton wallet (compute address from stateInit if needed): body = TEP-74 **Transfer** with `amount = msg.amount`, `destination = msg.toUserAddress`, etc.; send.

### 4.6 Getters

- Standard **getWalletData()** (balance, owner, minter, jettonWalletCode) for TEP-74 compatibility.
- **getLockedByTreasury()**: return `isLockedByTreasury`.

---

## 5. Contract 3: Dollar Minter (jetton contract)

**Purpose**: TEP-74 jetton minter. **Owner** and **treasury wallet address** are **fixed in storage** at deploy. Mints only to that treasury jetton wallet. Mint request includes **credited user** in payload; minter sends InternalTransfer to treasury wallet with that payload so the wallet can notify the treasury.

### 5.1 Storage

```tolk
struct DollarMinterStorage {
    totalSupply: coins
    mintable: bool = true
    owner: address              // fixed at deploy (e.g. treasury or admin; only owner can request mint)
    treasuryWalletAddress: address  // fixed at deploy; the one jetton wallet that is the treasury wallet
    jettonContent: cell
    jettonWalletCode: cell      // treasury wallet code (custom)
}
```

- **Fixed at deploy**: `owner`, `treasuryWalletAddress` (never changed). All mints go to `treasuryWalletAddress`; only `owner` (or an allowed caller) can request mint.

### 5.2 Mint request (from Treasury)

```tolk
struct (OP_MINT_TO_TREASURY) MintToTreasury {
    queryId: uint64
    amount: coins
    creditedUser: address
}
```

- Sender must be `storage.owner` (treasury or authorized). Minter sends **InternalTransfer** to **storage.treasuryWalletAddress** (fixed) with `amount`, `from = contract.getAddress()`, and **forwardPayload** (or customPayload) containing `creditedUser` so the treasury wallet can notify the treasury with **Credited**(creditedUser, amount).

### 5.3 Flow

1. Treasury receives **MintDollarForUser(userAddress)** from app/admin.
2. Treasury sends to **Dollar Minter**: **MintToTreasury** `{ queryId, amount: 1 dollar, creditedUser: userAddress }`.
3. Minter checks sender == treasury; sends **InternalTransfer** to **treasury jetton wallet** with forwardPayload/customPayload = userAddress.
4. Treasury wallet receives InternalTransfer; increases balance; sends **Credited(userAddress, amount)** to Treasury.
5. Treasury receives Credited; updates `lockedForUser[userAddress] += amount`, `totalLocked += amount`.

### 5.4 Getters

- **getJettonData()**: TEP-74 minter data (total_supply, mintable, owner, content, wallet code).
- **getTreasuryWalletAddress()**: return `storage.treasuryWalletAddress` (fixed).

---

## 6. Message flows (summary)

| Step | From → To | Message | Effect |
|------|-----------|---------|--------|
| Mint for user | App/Admin → Treasury | MintDollarForUser(user) | Treasury asks minter to mint |
| Mint | Treasury → Dollar Minter | MintToTreasury(amount, creditedUser) | Minter mints to treasury wallet |
| Mint | Dollar Minter → Treasury Wallet | InternalTransfer(amount, forwardPayload=user) | Wallet balance += amount |
| Credit | Treasury Wallet → Treasury | Credited(user, amount) | lockedForUser[user] += amount |
| Liquidity | App → Treasury | TON (AddLiquidity or plain) | Treasury balance += TON |
| Release | Admin → Treasury | ReleaseDollarToUser(user) | Treasury asks wallet to transfer to user |
| Transfer | Treasury → Treasury Wallet | TransferToUser(amount, user) | Wallet sends TEP-74 Transfer to user |

---

## 7. Serialization and layout

- Use **RemainingBitsAndRefs** (or a small struct with one address) for “credited user” in payload when **reading** in the treasury wallet; avoid `slice` as a deserialized field.
- **map<address, uint64>**: use Tolk stdlib `map` for `lockedForUser`; implement get/update/sum as per stdlib (get, set, iterate).
- **Opcodes**: Confirm OP_* values against TEP-74 for Transfer/InternalTransfer; choose unique opcodes for Credited, TransferToUser, MintDollarForUser, ReleaseDollarToUser, AddLiquidity.

---

## 8. Project layout

```
smc/
├── README.md
├── TOLK_SPEC.md
├── contracts/
│   ├── common/
│   │   ├── opcodes.tolk
│   │   └── errors.tolk
│   ├── treasury.tolk
│   ├── treasury-jetton-wallet.tolk
│   └── dollar-minter.tolk
├── wrappers/
├── tests/
└── scripts/
```

---

## 9. Checklist

- [ ] Opcodes and errors in `contracts/common`.
- [ ] **Treasury**: storage with map, MintDollarForUser → minter, Credited → update ledger, ReleaseDollarToUser → treasury wallet TransferToUser, AddLiquidity no-op; getters.
- [ ] **Treasury Jetton Wallet**: InternalTransfer → balance += amount, notify Credited(user, amount); TransferToUser (from treasury only) → TEP-74 Transfer to user.
- [ ] **Dollar Minter**: MintDollarForUser from treasury only; InternalTransfer to treasury wallet with creditedUser in payload.
- [ ] Invariant: sum(lockedForUser) = treasury wallet balance; optional minLiquidityToRelease.
- [ ] Use **contract.getAddress()**, **createMessage**, **lazy** load where appropriate.

---

## References

- [README.md](./README.md) — Treasury design and discussion
- [Tolk overview](https://docs.ton.org/v3/documentation/smart-contracts/tolk)
- [Tolk language guide](https://docs.ton.org/v3/documentation/smart-contracts/tolk/language-guide)
- [Tolk vs FunC: pack to/from cells](https://docs.ton.org/v3/documentation/smart-contracts/tolk/tolk-vs-func/pack-to-from-cells)
- [Tolk vs FunC: createMessage](https://docs.ton.org/v3/documentation/smart-contracts/tolk/tolk-vs-func/create-message)
- [TEP-74: Jettons](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md)
