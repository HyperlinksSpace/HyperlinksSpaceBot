from fastapi.testclient import TestClient
from main import API_KEY, app

client = TestClient(app)


def _headers() -> dict:
    if API_KEY:
        return {"X-API-Key": API_KEY}
    return {}


def test_wallet_create_response_shape():
    payload = {
        "user_id": "u1",
        "wallet_id": "w1",
        "address": "EQabc",
        "public_key": "pubkey1"
    }

    response = client.post("/wallet/create", json=payload, headers=_headers())
    assert response.status_code == 200

    data = response.json()

    # Basic shape contract
    assert "state" in data
    assert "ctx" in data

    assert data["state"] == "created"

    ctx = data["ctx"]
    assert ctx["user_id"] == "u1"
    assert ctx["wallet_id"] == "w1"
    assert ctx["address"] == "EQabc"
    assert ctx["public_key"] == "pubkey1"
