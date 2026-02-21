import pytest

from wallet.state_machine import WalletMachine, WalletState


def test_happy_path_created_allocated_active():
    m = WalletMachine.new(user_id="u1", wallet_id="w1")
    assert m.state == WalletState.INIT

    m = m.created(address="EQabc", public_key="pubkey1")
    assert m.state == WalletState.CREATED
    assert m.ctx.address == "EQabc"
    assert m.ctx.public_key == "pubkey1"

    m = m.allocated(amount="10", asset="DLLR", tx_ref="tx1")
    assert m.state == WalletState.ALLOCATED
    assert m.ctx.allocation_amount == "10"
    assert m.ctx.allocation_asset == "DLLR"
    assert m.ctx.allocation_tx_ref == "tx1"

    m = m.active()
    assert m.state == WalletState.ACTIVE


def test_optional_funded_step():
    m = WalletMachine.new(user_id="u1", wallet_id="w1").created(address="EQabc", public_key="pubkey1")
    m = m.allocated(amount="5", asset="DLLR").funded(tx_ref="fund_tx")
    assert m.state == WalletState.FUNDED
    assert m.ctx.allocation_tx_ref == "fund_tx"

    m = m.active()
    assert m.state == WalletState.ACTIVE


def test_invalid_transition_errors():
    m = WalletMachine.new(user_id="u1", wallet_id="w1")

    with pytest.raises(ValueError):
        m.allocated(amount="10")  # must be CREATED first

    with pytest.raises(ValueError):
        m.active()  # cannot activate from INIT


def test_created_requires_fields():
    m = WalletMachine.new(user_id="u1", wallet_id="w1")
    with pytest.raises(ValueError):
        m.created(address="", public_key="x")
    with pytest.raises(ValueError):
        m.created(address="x", public_key="")


def test_allocated_requires_amount_and_asset():
    m = WalletMachine.new(user_id="u1", wallet_id="w1").created(address="EQabc", public_key="pubkey1")

    with pytest.raises(ValueError):
        m.allocated(amount="")

    with pytest.raises(ValueError):
        m.allocated(amount="1", asset="")


def test_failed_allowed_from_any_state_and_is_terminal():
    m = WalletMachine.new(user_id="u1", wallet_id="w1")
    m2 = m.failed(error="boom")
    assert m2.state == WalletState.FAILED
    assert m2.ctx.last_error == "boom"

    # still allowed to call failed again with new message
    m3 = m2.failed(error="boom2")
    assert m3.state == WalletState.FAILED
    assert m3.ctx.last_error == "boom2"

    # other transitions should fail once FAILED
    with pytest.raises(ValueError):
        m3.created(address="EQabc", public_key="pubkey1")
