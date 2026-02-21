from __future__ import annotations

from dataclasses import asdict
from uuid import uuid4

from .state_machine import WalletMachine


class WalletService:
    """
    Thin orchestration layer around the pure WalletMachine state transitions.
    DB/persistence can be attached later without changing route handlers.
    """

    def create_wallet(
        self,
        *,
        user_id: str,
        wallet_id: str | None = None,
        address: str | None = None,
        public_key: str | None = None,
    ) -> WalletMachine:
        resolved_wallet_id = (wallet_id or "").strip() or f"w_{uuid4().hex[:12]}"
        resolved_address = (address or "").strip() or f"EQ{uuid4().hex[:46]}"
        resolved_public_key = (public_key or "").strip() or uuid4().hex

        machine = WalletMachine.new(user_id=user_id, wallet_id=resolved_wallet_id)
        return machine.created(address=resolved_address, public_key=resolved_public_key)

    def allocate(
        self,
        machine: WalletMachine,
        *,
        amount: str,
        asset: str = "DLLR",
        tx_ref: str | None = None,
    ) -> WalletMachine:
        return machine.allocated(amount=amount, asset=asset, tx_ref=tx_ref)

    def activate(self, machine: WalletMachine) -> WalletMachine:
        return machine.active()


def serialize_wallet_machine(machine: WalletMachine) -> dict:
    return {
        "state": machine.state.value,
        "context": asdict(machine.ctx),
    }
