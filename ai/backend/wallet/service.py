from __future__ import annotations

from dataclasses import asdict

from wallet.repo import WalletRepository, InMemoryWalletRepository
from wallet.state_machine import WalletMachine


class WalletService:
    """
    Thin orchestration layer around the pure WalletMachine state transitions.
    DB/persistence can be attached later without changing route handlers.
    """

    def __init__(self, repo: WalletRepository | None = None) -> None:
        self._repo: WalletRepository = repo or InMemoryWalletRepository()

    def get(self, wallet_id: str):
        return self._repo.get(wallet_id)

    def create_wallet(self, *, user_id: str, wallet_id: str, address: str, public_key: str):
        m = WalletMachine.new(user_id=user_id, wallet_id=wallet_id).created(
            address=address,
            public_key=public_key,
        )
        self._repo.save(m)
        return m

    def allocate(
        self,
        *,
        wallet_id: str,
        amount: str,
        asset: str = "DLLR",
        tx_ref: str | None = None,
    ):
        m = self._repo.get(wallet_id)
        if m is None:
            raise ValueError("wallet_not_found")

        m2 = m.allocated(amount=amount, asset=asset, tx_ref=tx_ref)
        self._repo.save(m2)
        return m2

    def activate(self, *, wallet_id: str):
        m = self._repo.get(wallet_id)
        if m is None:
            raise ValueError("wallet_not_found")

        m2 = m.active()
        self._repo.save(m2)
        return m2


def serialize_wallet_machine(machine: WalletMachine) -> dict:
    return {
        "state": machine.state.value,
        "ctx": asdict(machine.ctx),
    }
