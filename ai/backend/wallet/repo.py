from __future__ import annotations

from dataclasses import replace
from typing import Dict, Optional, Protocol

from wallet.models import WalletRecord
from wallet.state_machine import WalletContext, WalletMachine, WalletState


class WalletRepository(Protocol):
    def save(self, machine: WalletMachine) -> None: ...
    def get(self, wallet_id: str) -> Optional[WalletMachine]: ...


def machine_to_record(machine: WalletMachine) -> WalletRecord:
    ctx = machine.ctx
    return WalletRecord(
        wallet_id=ctx.wallet_id,
        user_id=ctx.user_id,
        state=machine.state.value,
        address=ctx.address,
        public_key=ctx.public_key,
        allocation_amount=ctx.allocation_amount,
        allocation_asset=ctx.allocation_asset,
        allocation_tx_ref=ctx.allocation_tx_ref,
    )


def record_to_machine(record: WalletRecord) -> WalletMachine:
    state = WalletState(record.state)
    ctx = WalletContext(
        user_id=record.user_id,
        wallet_id=record.wallet_id,
        address=record.address,
        public_key=record.public_key,
        allocation_amount=record.allocation_amount,
        allocation_asset=record.allocation_asset,
        allocation_tx_ref=record.allocation_tx_ref,
    )
    return WalletMachine(state=state, ctx=ctx)


class InMemoryWalletRepository:
    """
    Simple in-memory repo for local dev/tests.
    Swap with Postgres/Supabase later without touching service logic.
    """
    def __init__(self) -> None:
        self._by_wallet_id: Dict[str, WalletMachine] = {}

    def save(self, machine: WalletMachine) -> None:
        # store a fresh immutable copy (defensive)
        self._by_wallet_id[machine.ctx.wallet_id] = replace(machine)

    def get(self, wallet_id: str) -> Optional[WalletMachine]:
        return self._by_wallet_id.get(wallet_id)
