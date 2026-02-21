from __future__ import annotations

from dataclasses import dataclass, replace
from enum import Enum
from typing import Optional


class WalletState(str, Enum):
    # lifecycle
    INIT = "init"
    CREATED = "created"          # wallet keys/address created (non-custodial)
    ALLOCATED = "allocated"      # DLLR allocation prepared/assigned
    FUNDED = "funded"            # on-chain funding confirmed (optional step)
    ACTIVE = "active"            # ready for use
    FAILED = "failed"            # terminal failure state


@dataclass(frozen=True)
class WalletContext:
    user_id: str
    wallet_id: str

    address: Optional[str] = None
    public_key: Optional[str] = None

    # allocation metadata (keep generic; can map to DLLR later)
    allocation_amount: Optional[str] = None
    allocation_asset: Optional[str] = None
    allocation_tx_ref: Optional[str] = None

    # operational metadata
    last_error: Optional[str] = None


@dataclass(frozen=True)
class WalletMachine:
    state: WalletState
    ctx: WalletContext

    @staticmethod
    def new(*, user_id: str, wallet_id: str) -> "WalletMachine":
        return WalletMachine(
            state=WalletState.INIT,
            ctx=WalletContext(user_id=user_id, wallet_id=wallet_id),
        )

    # ----- transitions (pure functions) -----

    def created(self, *, address: str, public_key: str) -> "WalletMachine":
        self._require_state(WalletState.INIT)
        if not address or not public_key:
            raise ValueError("address and public_key are required")
        return replace(
            self,
            state=WalletState.CREATED,
            ctx=replace(self.ctx, address=address, public_key=public_key, last_error=None),
        )

    def allocated(
        self,
        *,
        amount: str,
        asset: str = "DLLR",
        tx_ref: Optional[str] = None,
    ) -> "WalletMachine":
        self._require_state(WalletState.CREATED)
        if not amount or amount.strip() == "":
            raise ValueError("amount is required")
        if not asset or asset.strip() == "":
            raise ValueError("asset is required")
        return replace(
            self,
            state=WalletState.ALLOCATED,
            ctx=replace(
                self.ctx,
                allocation_amount=amount,
                allocation_asset=asset,
                allocation_tx_ref=tx_ref,
                last_error=None,
            ),
        )

    def funded(self, *, tx_ref: Optional[str] = None) -> "WalletMachine":
        # optional step: some flows may skip FUNDED and go straight to active()
        self._require_state(WalletState.ALLOCATED)
        return replace(
            self,
            state=WalletState.FUNDED,
            ctx=replace(self.ctx, allocation_tx_ref=tx_ref or self.ctx.allocation_tx_ref, last_error=None),
        )

    def active(self) -> "WalletMachine":
        if self.state not in (WalletState.ALLOCATED, WalletState.FUNDED):
            raise ValueError(f"cannot activate from state={self.state}")
        return replace(self, state=WalletState.ACTIVE, ctx=replace(self.ctx, last_error=None))

    def failed(self, *, error: str) -> "WalletMachine":
        if not error or error.strip() == "":
            raise ValueError("error is required")
        # failure allowed from any state (non-throwing cleanup)
        return replace(self, state=WalletState.FAILED, ctx=replace(self.ctx, last_error=error))

    # ----- helpers -----

    def _require_state(self, expected: WalletState) -> None:
        if self.state != expected:
            raise ValueError(f"invalid transition from state={self.state}, expected={expected}")
