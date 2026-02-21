from dataclasses import dataclass


@dataclass
class WalletRecord:
    wallet_id: str
    user_id: str
    state: str
    address: str | None
    public_key: str | None
    allocation_amount: str | None
    allocation_asset: str | None
    allocation_tx_ref: str | None
