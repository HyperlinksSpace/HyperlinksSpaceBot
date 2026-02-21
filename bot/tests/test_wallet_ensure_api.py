import asyncio
import json

import pytest

# Skip gracefully if bot runtime deps are not installed in the current env.
pytest.importorskip("telegram")
pytest.importorskip("aiohttp")

from bot import bot as bot_module


class DummyRequest:
    def __init__(self, payload=None, headers=None, path="/wallet/ensure"):
        self._payload = payload if payload is not None else {}
        self.headers = headers or {}
        self.path = path
        self.remote = "test"

    async def json(self):
        return self._payload


def _call_wallet_ensure(request: DummyRequest):
    return asyncio.run(bot_module.http_wallet_ensure_handler(request))


def _json(response):
    return json.loads(response.text)


def test_wallet_ensure_assigned(monkeypatch):
    monkeypatch.setenv("INNER_CALLS_KEY", "k")

    async def _claim(_username: str) -> str:
        return "assigned"

    monkeypatch.setattr(bot_module, "claim_wallet_for_username", _claim)

    resp = _call_wallet_ensure(DummyRequest(payload={"username": "alice"}, headers={"X-API-Key": "k"}))
    assert resp.status == 200
    assert _json(resp) == {
        "status": "ok",
        "wallet_status": "assigned",
        "newly_assigned": True,
    }


def test_wallet_ensure_already_assigned(monkeypatch):
    monkeypatch.setenv("INNER_CALLS_KEY", "k")

    async def _claim(_username: str) -> str:
        return "already_assigned"

    monkeypatch.setattr(bot_module, "claim_wallet_for_username", _claim)

    resp = _call_wallet_ensure(DummyRequest(payload={"username": "alice"}, headers={"X-API-Key": "k"}))
    assert resp.status == 200
    assert _json(resp) == {
        "status": "ok",
        "wallet_status": "already_assigned",
        "newly_assigned": False,
    }


def test_wallet_ensure_user_not_found(monkeypatch):
    monkeypatch.setenv("INNER_CALLS_KEY", "k")

    async def _claim(_username: str) -> str:
        return "user_not_found"

    monkeypatch.setattr(bot_module, "claim_wallet_for_username", _claim)

    resp = _call_wallet_ensure(DummyRequest(payload={"username": "ghost"}, headers={"X-API-Key": "k"}))
    assert resp.status == 404
    assert _json(resp) == {"error": "user_not_found"}


def test_wallet_ensure_invalid_username(monkeypatch):
    monkeypatch.setenv("INNER_CALLS_KEY", "k")

    resp = _call_wallet_ensure(DummyRequest(payload={}, headers={"X-API-Key": "k"}))
    assert resp.status == 400
    assert _json(resp) == {"error": "username is required."}


def test_wallet_ensure_db_unavailable(monkeypatch):
    monkeypatch.setenv("INNER_CALLS_KEY", "k")

    async def _claim(_username: str) -> str:
        return "db_unavailable"

    monkeypatch.setattr(bot_module, "claim_wallet_for_username", _claim)

    resp = _call_wallet_ensure(DummyRequest(payload={"username": "alice"}, headers={"X-API-Key": "k"}))
    assert resp.status == 503
    assert _json(resp) == {"error": "database_unavailable"}


def test_wallet_ensure_auth_missing_and_invalid_key(monkeypatch):
    monkeypatch.setenv("INNER_CALLS_KEY", "k")

    missing = _call_wallet_ensure(DummyRequest(payload={"username": "alice"}, headers={}))
    assert missing.status == 401

    invalid = _call_wallet_ensure(DummyRequest(payload={"username": "alice"}, headers={"X-API-Key": "bad"}))
    assert invalid.status == 403
