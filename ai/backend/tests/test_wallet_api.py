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


def test_wallet_create_and_get_flow():
    payload = {
        "user_id": "u2",
        "wallet_id": "w2",
        "address": "EQxyz",
        "public_key": "pubkey2"
    }

    # Create
    r1 = client.post("/wallet/create", json=payload, headers=_headers())
    assert r1.status_code == 200
    data1 = r1.json()
    assert data1["state"] == "created"

    # Fetch
    r2 = client.get("/wallet/w2")
    assert r2.status_code == 200
    data2 = r2.json()

    assert data2["ctx"]["wallet_id"] == "w2"
    assert data2["ctx"]["address"] == "EQxyz"
    assert data2["state"] == "created"


def test_wallet_allocate_and_activate_flow():
    payload = {
        "user_id": "u3",
        "wallet_id": "w3",
        "address": "EQalloc",
        "public_key": "pubkey3"
    }

    # Create
    r1 = client.post("/wallet/create", json=payload, headers=_headers())
    assert r1.status_code == 200
    assert r1.json()["state"] == "created"

    # Allocate
    r2 = client.post("/wallet/w3/allocate", json={"amount": "25"})
    assert r2.status_code == 200
    assert r2.json()["state"] == "allocated"
    assert r2.json()["ctx"]["allocation_amount"] == "25"

    # Activate
    r3 = client.post("/wallet/w3/activate")
    assert r3.status_code == 200
    assert r3.json()["state"] == "active"
