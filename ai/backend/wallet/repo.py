from __future__ import annotations

from dataclasses import replace
from typing import Dict, Optional, Protocol

from wallet.state_machine import WalletMachine


class WalletRepository(Protocol):
    def save(self, machine: WalletMachine) -> None: ...
    def get(self, wallet_id: str) -> Optional[WalletMachine]: ...


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
