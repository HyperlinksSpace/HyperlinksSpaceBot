from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from wallet.models import WalletRecord
from wallet.repo import WalletRepository, machine_to_record, record_to_machine
from wallet.state_machine import WalletMachine


@dataclass(frozen=True)
class PostgresConfig:
    """
    Config placeholder. We'll wire DATABASE_URL + pool later.
    Keeping it explicit prevents leaking DB concerns into service/API.
    """
    database_url: str


class PostgresWalletRepository(WalletRepository):
    """
    Stub repository to keep architecture ready for real persistence.

    Intentionally not implemented yet:
    - choose driver (psycopg vs asyncpg)
    - connection pooling
    - migrations runner strategy
    """
    def __init__(self, cfg: PostgresConfig) -> None:
        self._cfg = cfg

    def save(self, machine: WalletMachine) -> None:
        record: WalletRecord = machine_to_record(machine)
        raise NotImplementedError("PostgresWalletRepository.save not implemented yet")

    def get(self, wallet_id: str) -> Optional[WalletMachine]:
        raise NotImplementedError("PostgresWalletRepository.get not implemented yet")

    # Optional helpers for future wiring (kept here for clarity)
    @staticmethod
    def _record_to_machine(record: WalletRecord) -> WalletMachine:
        return record_to_machine(record)
