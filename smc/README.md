# Smart Contract Technical Task: Welcome Token & NFT Vesting System

## Overview

This document outlines the technical requirements for implementing a vesting-based welcome bonus system for new users. The system consists of:

1. **Welcome Jetton (Token)** - A fungible token worth $1 that is locked until released by admin
2. **Welcome NFT** - A non-fungible token (badge) that is locked until released by admin
3. **Vesting Contract** - A smart contract that locks jettons and NFTs, preventing transfers until admin release
4. **Minter Contracts** - Standard-compliant jetton minter and NFT collection contracts

## Business Requirements

### User Flow
1. When a new user registers in the app:
   - A wallet is created for the user
   - A welcome jetton ($1 value) is minted and sent to a **vesting contract** (not directly to user)
   - A welcome NFT (badge) is minted and sent to a **vesting contract** (not directly to user)
   - User can see their welcome bonuses in the UI but cannot use/transfer them yet

2. When the app becomes popular (admin decision):
   - Admin calls `releaseVesting()` on vesting contracts
   - Locked jettons are released to the user's wallet
   - Locked NFTs are released to the user's wallet
   - User can now transfer, swap, or use their welcome bonuses

### Key Constraints
- Users **CANNOT** send/swap jettons while they are locked in vesting
- Users **CANNOT** transfer NFTs while they are locked in vesting
- Only the admin can unlock vesting (centralized release)
- All tokens must comply with TON standards (TEP-74 for jettons, TEP-62 for NFTs)

## Architecture

```
┌─────────────────┐
│  User's Wallet  │
└────────┬────────┘
         │
         │ (after release)
         ↓
┌──────────────────────────────────┐
│     Vesting Jetton Wallet        │ ← Holds locked jettons
│  - Stores user address           │
│  - Stores jetton balance         │
│  - Prevents transfers when locked│
└──────────────────────────────────┘
         ↑
         │ (minted here)
┌──────────────────────────────────┐
│      Jetton Minter Contract      │
│  - Standard TEP-74 compliant     │
│  - Mints welcome jettons         │
└──────────────────────────────────┘

┌─────────────────┐
│  User's Wallet  │
└────────┬────────┘
         │
         │ (after release)
         ↓
┌──────────────────────────────────┐
│      Vesting NFT Item            │ ← Holds locked NFT
│  - Stores user address           │
│  - Stores NFT ownership          │
│  - Prevents transfers when locked│
└──────────────────────────────────┘
         ↑
         │ (minted here)
┌──────────────────────────────────┐
│      NFT Collection Contract     │
│  - Standard TEP-62 compliant     │
│  - Mints welcome NFTs            │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│         Admin Contract           │
│  - Controls vesting release      │
│  - Can release all vestings      │
└──────────────────────────────────┘
```

## Smart Contract Specifications

### 1. Vesting Jetton Wallet Contract

**Purpose**: Holds jettons for a user but prevents transfers until unlocked.

**Standard Compliance**: TEP-74 Jetton Wallet (with vesting extension)

**Storage Structure**:
```tolk
struct VestingJettonWalletStorage {
    balance: coins                    // Jetton balance
    owner: address                    // User address (beneficiary)
    minter: address                   // Jetton minter address
    jettonWalletCode: cell            // Standard jetton wallet code
    isLocked: bool = true             // Vesting lock status
    vestingReleaseAddress: address    // Admin contract that can release
}
```

**Key Features**:
- Implements standard jetton wallet interface (TEP-74)
- **Transfer Prevention**: When `isLocked == true`, all transfer operations throw an error
- **Admin Release**: Only `vestingReleaseAddress` can call `release()` to unlock
- **Balance Visibility**: Users can check balance via standard `get_wallet_data()` getter

**Messages**:

1. **Standard TEP-74 Transfer** (blocked when locked):
   ```tolk
   struct (0x0f8a7ea5) Transfer {
       queryId: uint64
       amount: coins
       destination: address
       responseDestination: address?
       customPayload: cell?
       forwardTonAmount: coins
       forwardPayload: slice
   }
   ```
   - Must check `isLocked` and throw if `true`
   - Standard operation when unlocked

2. **Release Vesting** (admin only):
   ```tolk
   struct (0x12345678) ReleaseVesting {
       queryId: uint64
   }
   ```
   - Checks sender == `vestingReleaseAddress`
   - Sets `isLocked = false`
   - Optionally sends notification to user

3. **Internal Transfer Receive** (from minter):
   ```tolk
   struct (0x178d4519) InternalTransfer {
       queryId: uint64
       amount: coins
       from: address
       responseDestination: address?
       forwardTonAmount: coins
       forwardPayload: slice
   }
   ```
   - Allows receiving jettons from minter (for minting)
   - Updates balance

**Getters**:
- `get_wallet_data()` - Returns standard jetton wallet data (TEP-74)
- `get_vesting_status()` - Returns `(isLocked: bool, releaseAddress: address)`

**Entrypoints**:
```tolk
fun onInternalMessage(in: InMessage) {
    // Handle Transfer, InternalTransfer, ReleaseVesting
    // Match opcode and process accordingly
}
```

### 2. Jetton Minter Contract

**Purpose**: Standard jetton minter that mints welcome tokens to vesting wallets.

**Standard Compliance**: TEP-74 Jetton Minter

**Storage Structure**:
```tolk
struct JettonMinterStorage {
    totalSupply: coins
    mintable: bool = true
    adminAddress: address
    jettonContent: cell                    // Metadata
    jettonWalletCode: cell                 // Standard wallet code
    vestingWalletCode: cell                // Vesting wallet code
    vestingReleaseAddress: address         // Admin that can release vestings
}
```

**Key Features**:
- Standard TEP-74 jetton minter
- Mints directly to vesting wallets (not regular wallets)
- Calculates vesting wallet address deterministically

**Messages**:

1. **Mint Welcome Token** (admin only):
   ```tolk
   struct (0x00000000) MintWelcomeToken {
       queryId: uint64
       amount: coins = ton("1000000000")  // $1 worth (1 billion nanocoins = 1 jetton with 9 decimals)
       destination: address                // User's wallet address
   }
   ```
   - Calculates vesting wallet address
   - Deploys vesting wallet if needed
   - Mints jettons to vesting wallet
   - Updates total supply

**Getters**:
- `get_jetton_data()` - Standard TEP-74 getter
- `get_wallet_address(ownerAddress: address)` - Returns vesting wallet address for user

**Deployment Logic**:
```tolk
fun calcVestingWalletAddress(ownerAddress: address): AutoDeployAddress {
    val storage: VestingJettonWalletStorage = {
        balance: 0,
        owner: ownerAddress,
        minter: contract.myAddress(),
        jettonWalletCode: storage.vestingWalletCode,
        isLocked: true,
        vestingReleaseAddress: storage.vestingReleaseAddress
    };
    
    return {
        stateInit: {
            code: storage.vestingWalletCode,
            data: storage.toCell()
        },
        toShard: {
            closeTo: ownerAddress,
            fixedPrefixLength: 8
        }
    }
}
```

### 3. Vesting NFT Item Contract

**Purpose**: Holds NFT for a user but prevents transfers until unlocked.

**Standard Compliance**: TEP-62 NFT Item (with vesting extension)

**Storage Structure**:
```tolk
struct VestingNftItemStorage {
    index: uint64                          // NFT index in collection
    collectionAddress: address             // NFT collection address
    ownerAddress: address                  // User address (beneficiary)
    content: cell                          // NFT metadata/content
    isLocked: bool = true                  // Vesting lock status
    vestingReleaseAddress: address         // Admin contract that can release
}
```

**Key Features**:
- Implements standard NFT item interface (TEP-62)
- **Transfer Prevention**: When `isLocked == true`, transfer throws error
- **Admin Release**: Only `vestingReleaseAddress` can unlock
- **Ownership Visibility**: Users can check ownership via standard getters

**Messages**:

1. **Standard TEP-62 Transfer** (blocked when locked):
   ```tolk
   struct (0x5fcc3d14) Transfer {
       queryId: uint64
       newOwner: address
       responseDestination: address?
       customPayload: cell?
       forwardAmount: coins
       forwardPayload: slice
   }
   ```
   - Must check `isLocked` and throw if `true`
   - Standard operation when unlocked

2. **Release Vesting** (admin only):
   ```tolk
   struct (0x12345678) ReleaseVesting {
       queryId: uint64
   }
   ```
   - Sets `isLocked = false`

3. **Ownership Assignment** (from collection during mint):
   - Standard NFT initialization
   - Sets `ownerAddress` and `isLocked = true`

**Getters**:
- `get_nft_data()` - Standard TEP-62 getter
- `get_vesting_status()` - Returns `(isLocked: bool, releaseAddress: address)`

### 4. NFT Collection Contract

**Purpose**: Standard NFT collection that mints welcome NFTs to vesting items.

**Standard Compliance**: TEP-62 NFT Collection

**Storage Structure**:
```tolk
struct NftCollectionStorage {
    nextItemIndex: uint64
    collectionContent: cell                // Collection metadata
    ownerAddress: address                  // Collection owner (admin)
    nftItemCode: cell                      // Standard NFT item code
    vestingItemCode: cell                  // Vesting NFT item code
    vestingReleaseAddress: address         // Admin that can release vestings
}
```

**Key Features**:
- Standard TEP-62 NFT collection
- Mints directly to vesting NFT items
- Stores welcome NFT content/metadata

**Messages**:

1. **Mint Welcome NFT** (admin only):
   ```tolk
   struct (0x00000001) MintWelcomeNft {
       queryId: uint64
       ownerAddress: address               // User's wallet address
       content: cell                       // NFT content/metadata
   }
   ```
   - Calculates vesting NFT item address
   - Deploys vesting NFT item
   - Initializes NFT with locked status

**Getters**:
- `get_collection_data()` - Standard TEP-62 getter
- `get_nft_address_by_index(index: uint64)` - Returns vesting NFT item address

### 5. Admin/Vesting Release Contract (Optional)

**Purpose**: Centralized contract to release all vestings at once.

**Storage Structure**:
```tolk
struct AdminStorage {
    adminAddress: address
    jettonMinterAddress: address
    nftCollectionAddress: address
}
```

**Messages**:

1. **Release All Vestings**:
   ```tolk
   struct (0xABCDEF01) ReleaseAllVestings {
       queryId: uint64
       userAddresses: slice                // List of user addresses (or single address)
   }
   ```
   - Iterates through user addresses
   - Calculates vesting wallet/NFT addresses
   - Sends `ReleaseVesting` to each
   - Only callable by `adminAddress`

2. **Release Single User Vesting**:
   ```tolk
   struct (0xABCDEF02) ReleaseUserVesting {
       queryId: uint64
       userAddress: address
   }
   ```
   - Releases both jetton and NFT vesting for a single user

**Alternative Approach**: Admin can directly call `ReleaseVesting` on vesting contracts (no separate admin contract needed).

## Implementation Strategy

### Phase 1: Core Infrastructure

1. **Study TON Standards**:
   - [ ] Review TEP-74 (Jettons Standard) specification
   - [ ] Review TEP-62 (NFT Standard) specification
   - [ ] Review reference implementations in Tolk
   - [ ] Understand message formats and opcodes

2. **Set Up Project Structure**:
   ```
   smc/
   ├── README.md (this file)
   ├── contracts/
   │   ├── jetton/
   │   │   ├── jetton-minter.tolk
   │   │   ├── vesting-jetton-wallet.tolk
   │   │   └── storage.tolk
   │   ├── nft/
   │   │   ├── nft-collection.tolk
   │   │   ├── vesting-nft-item.tolk
   │   │   └── storage.tolk
   │   └── admin/
   │       └── vesting-release.tolk (optional)
   ├── common/
   │   ├── errors.tolk
   │   ├── constants.tolk
   │   └── opcodes.tolk
   ├── tests/
   │   └── (test files)
   └── scripts/
       └── deploy.tolk
   ```

3. **Define Common Constants**:
   ```tolk
   // opcodes.tolk
   const OP_TRANSFER = 0x0f8a7ea5
   const OP_INTERNAL_TRANSFER = 0x178d4519
   const OP_RELEASE_VESTING = 0x12345678
   const OP_MINT_WELCOME_TOKEN = 0x00000000
   const OP_MINT_WELCOME_NFT = 0x00000001
   const OP_NFT_TRANSFER = 0x5fcc3d14
   
   // errors.tolk
   const ERROR_VESTING_LOCKED = 401
   const ERROR_UNAUTHORIZED = 403
   const ERROR_INVALID_STATE = 404
   ```

### Phase 2: Jetton Implementation

1. **Implement Vesting Jetton Wallet**:
   - [ ] Create storage structure
   - [ ] Implement standard TEP-74 transfer (with lock check)
   - [ ] Implement internal transfer receive (for minting)
   - [ ] Implement release vesting message
   - [ ] Implement standard getters
   - [ ] Add address calculation helper
   - [ ] Test lock/unlock functionality

2. **Implement Jetton Minter**:
   - [ ] Create storage structure
   - [ ] Implement welcome token minting
   - [ ] Implement vesting wallet deployment
   - [ ] Implement standard TEP-74 getters
   - [ ] Test minting flow

### Phase 3: NFT Implementation

1. **Implement Vesting NFT Item**:
   - [ ] Create storage structure
   - [ ] Implement standard TEP-62 transfer (with lock check)
   - [ ] Implement release vesting message
   - [ ] Implement standard getters
   - [ ] Add address calculation helper
   - [ ] Test lock/unlock functionality

2. **Implement NFT Collection**:
   - [ ] Create storage structure
   - [ ] Implement welcome NFT minting
   - [ ] Implement vesting NFT item deployment
   - [ ] Implement standard TEP-62 getters
   - [ ] Test minting flow

### Phase 4: Integration & Testing

1. **End-to-End Testing**:
   - [ ] Test complete user onboarding flow
   - [ ] Test minting welcome token + NFT
   - [ ] Test locked state (attempted transfers should fail)
   - [ ] Test admin release
   - [ ] Test unlocked state (transfers should work)
   - [ ] Test edge cases (bounced messages, invalid addresses, etc.)

2. **Gas Optimization**:
   - [ ] Review gas consumption
   - [ ] Optimize storage operations
   - [ ] Use lazy loading where appropriate

3. **Security Audit**:
   - [ ] Review access controls
   - [ ] Test reentrancy scenarios
   - [ ] Verify standard compliance
   - [ ] Test with various malformed messages

## Technical Considerations

### Vesting Wallet Address Calculation

Vesting wallets must have deterministic addresses so:
1. The minter can calculate the address before minting
2. The frontend can query vesting status
3. Admin can send release messages

Use Tolk's `createMessage` with `stateInit` for deterministic address calculation:

```tolk
fun calcVestingJettonWalletAddress(ownerAddress: address, minterAddress: address): address {
    val storage: VestingJettonWalletStorage = {
        balance: 0,
        owner: ownerAddress,
        minter: minterAddress,
        jettonWalletCode: CODE,
        isLocked: true,
        vestingReleaseAddress: RELEASE_ADDRESS
    };
    
    val stateInit = {
        code: CODE,
        data: storage.toCell()
    };
    
    return stateInit.address();
}
```

### Sharding Strategy

Deploy vesting wallets close to user wallets for better sharding:
```tolk
toShard: {
    closeTo: ownerAddress,
    fixedPrefixLength: 8
}
```

### Message Flow: Minting Welcome Token

1. Admin sends `MintWelcomeToken` to Jetton Minter
2. Minter calculates vesting wallet address
3. Minter creates deployment message for vesting wallet
4. Minter sends `InternalTransfer` to vesting wallet (deploys it)
5. Vesting wallet receives tokens, balance updated, `isLocked = true`

### Message Flow: Releasing Vesting

1. Admin sends `ReleaseVesting` to Vesting Wallet (or uses Admin Contract)
2. Vesting Wallet verifies sender == `vestingReleaseAddress`
3. Vesting Wallet sets `isLocked = false`
4. User can now transfer jettons normally

### Forward Payload Handling

When jettons are locked, transfer attempts should fail **before** processing forward payload. This prevents partial state changes.

## Integration with Frontend

### Required Frontend Operations

1. **On User Registration**:
   ```dart
   // Pseudocode
   await jettonMinter.mintWelcomeToken(userAddress);
   await nftCollection.mintWelcomeNft(userAddress, welcomeNftContent);
   ```

2. **Check Vesting Status**:
   ```dart
   val vestingWalletAddress = jettonMinter.getWalletAddress(userAddress);
   val vestingData = vestingWallet.getVestingStatus();
   // Returns: (isLocked: bool, balance: coins)
   ```

3. **Display Locked Status in UI**:
   - Show balance but indicate "Locked" status
   - Disable transfer/swap buttons when locked
   - Show message: "Welcome bonus will be unlocked when app launches"

4. **Admin Release** (when app becomes popular):
   ```dart
   await adminContract.releaseAllVestings(userAddresses);
   // Or individually:
   await vestingWallet.release();
   await vestingNft.release();
   ```

## Testing Checklist

- [ ] Unit tests for each contract
- [ ] Integration tests for minting flow
- [ ] Integration tests for release flow
- [ ] Test locked transfer rejection
- [ ] Test unlocked transfer success
- [ ] Test unauthorized access attempts
- [ ] Test edge cases (zero balance, max balance, etc.)
- [ ] Test with TON testnet
- [ ] Gas consumption benchmarks
- [ ] Standard compliance verification

## Deployment Plan

1. **Testnet Deployment**:
   - Deploy all contracts to TON testnet
   - Test complete flow with test accounts
   - Verify standard compliance with TON explorers

2. **Mainnet Deployment**:
   - Deploy contracts to TON mainnet
   - Configure admin addresses
   - Initialize minter and collection
   - Set vesting release address

3. **Monitoring**:
   - Monitor contract activity
   - Track vesting wallet deployments
   - Monitor gas consumption
   - Set up alerts for errors

## Future Enhancements

- **Time-based Vesting**: Add gradual unlock over time
- **Batch Release**: Optimize gas for releasing multiple vestings
- **Vesting Events**: Emit logs for off-chain indexing
- **Multi-token Vesting**: Support multiple jetton types per user
- **Partial Release**: Allow partial unlocking of vesting

## References

- [TEP-74: Jettons Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0074-jettons-standard.md)
- [TEP-62: NFT Standard](https://github.com/ton-blockchain/TEPs/blob/master/text/0062-nft-standard.md)
- [Tolk Language Documentation](https://docs.ton.org/v3/documentation/smart-contracts/tolk)
- [TON Token Contract Reference](https://github.com/ton-blockchain/token-contract)

## Notes

- All opcodes are examples and should be confirmed against TON standards
- Decimal precision for welcome token should match TON/USD conversion (likely 9 decimals)
- Welcome NFT content/metadata format should follow TEP-64 standard
- Consider implementing upgrade mechanisms for admin contracts
- Gas costs should be optimized for batch operations

---

**Status**: 📋 Technical Task - Ready for Implementation  
**Last Updated**: 2025-01-XX  
**Next Steps**: Add TON standard specifications to folder, begin Phase 1 implementation

