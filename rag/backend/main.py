from fastapi import FastAPI, Depends, Header, HTTPException
from pathlib import Path
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import os, json
import hashlib
from datetime import datetime
import urllib.request
import urllib.error
import urllib.parse
import time

app = FastAPI()

BASE_DIR = Path(__file__).resolve().parent
ALLOWLIST_PATH = BASE_DIR.parent / "data" / "projects_allowlist.json"

STORE_PATH = os.getenv("RAG_STORE_PATH", "rag_store.json")
PROJECTS_STORE_PATH = os.getenv("PROJECTS_STORE_PATH", "projects_store.json")
SWAP_COFFEE_BASE_URL = (
    os.getenv("COFFEE_URL")
    or os.getenv("TOKENS_API_URL")
    or "https://tokens.swap.coffee"
).strip().rstrip("/")
COFFEE_KEY = (os.getenv("COFFEE_KEY") or os.getenv("TOKENS_API_KEY") or "").strip()
INNER_CALLS_KEY = (os.getenv("INNER_CALLS_KEY") or os.getenv("API_KEY") or "").strip()
TOKENS_VERIFICATION = os.getenv("TOKENS_VERIFICATION", "WHITELISTED,COMMUNITY,UNKNOWN")


def _mask_secret(value: str, visible: int = 4) -> str:
    if not value:
        return "(missing)"
    if len(value) <= visible * 2:
        return "*" * len(value)
    return f"{value[:visible]}...{value[-visible:]}"


def _key_fingerprint(value: str) -> str:
    if not value:
        return "(missing)"
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:6]


def _log_runtime_env_snapshot() -> None:
    print("[ENV][RAG] runtime configuration snapshot")
    print(f"[ENV][RAG] INNER_CALLS_KEY configured={bool(INNER_CALLS_KEY)} preview={_mask_secret(INNER_CALLS_KEY)}")
    print(f"[ENV][RAG] INNER_CALLS_KEY sha256_prefix={_key_fingerprint(INNER_CALLS_KEY)}")
    print(f"[ENV][RAG] SWAP_COFFEE_BASE_URL={SWAP_COFFEE_BASE_URL}")
    print(f"[ENV][RAG] COFFEE_KEY configured={bool(COFFEE_KEY)} preview={_mask_secret(COFFEE_KEY)}")


_log_runtime_env_snapshot()


def _first_non_none(*values):
    for v in values:
        if v is not None:
            return v
    return None


def verify_inner_calls_key(x_api_key: Optional[str] = Header(None, alias="X-API-Key")):
    # Keep /health open; enforce key on data endpoints.
    if not INNER_CALLS_KEY:
        raise HTTPException(status_code=503, detail="INNER_CALLS_KEY is not configured.")
    if not x_api_key:
        raise HTTPException(status_code=401, detail="X-API-Key header is required.")
    if x_api_key != INNER_CALLS_KEY:
        raise HTTPException(status_code=403, detail="Invalid API key")
    return x_api_key

def load_store() -> List[Dict[str, Any]]:
    if not os.path.exists(STORE_PATH):
        return []
    try:
        return json.loads(open(STORE_PATH, "r", encoding="utf-8").read())
    except:
        return []

def save_store(docs: List[Dict[str, Any]]) -> None:
    with open(STORE_PATH, "w", encoding="utf-8") as f:
        f.write(json.dumps(docs, ensure_ascii=False, indent=2))

def load_projects() -> List[Dict[str, Any]]:
    if not os.path.exists(PROJECTS_STORE_PATH):
        return []
    try:
        return json.loads(open(PROJECTS_STORE_PATH, "r", encoding="utf-8").read())
    except:
        return []

def save_projects(projects: List[Dict[str, Any]]) -> None:
    with open(PROJECTS_STORE_PATH, "w", encoding="utf-8") as f:
        f.write(json.dumps(projects, ensure_ascii=False, indent=2))
def _normalize_symbol(symbol: str) -> str:
    if symbol is None:
        return ""
    cleaned = symbol.replace("$", "").replace(" ", "").strip()
    return cleaned.upper()

def fetch_token_by_symbol(symbol: str) -> Dict[str, Any]:
    qs = urllib.parse.urlencode({"search": symbol, "size": 10, "verification": TOKENS_VERIFICATION})
    url = f"{SWAP_COFFEE_BASE_URL}/api/v3/jettons?{qs}"
    started = time.monotonic()
    try:
        req = urllib.request.Request(url)
        if COFFEE_KEY:
            req.add_header("X-Api-Key", COFFEE_KEY)
        with urllib.request.urlopen(req, timeout=10) as resp:
            status = getattr(resp, "status", 200)
            body = resp.read().decode("utf-8", errors="ignore")
            if status != 200:
                return {
                    "error": "unavailable",
                    "reason": "non_200",
                    "status_code": status,
                    "response_snippet": body[:200],
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                    "source": "swap.coffee",
                }
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                return {
                    "error": "unavailable",
                    "reason": "json_parse",
                    "status_code": status,
                    "response_snippet": body[:200],
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                    "source": "swap.coffee",
                }
            if not isinstance(data, list):
                return {
                    "error": "unavailable",
                    "reason": "unexpected_payload",
                    "status_code": status,
                    "response_snippet": body[:200],
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                    "source": "swap.coffee",
                }
            for item in data:
                if str(item.get("symbol", "")).upper() == symbol:
                    return {"data": item, "elapsed_ms": int((time.monotonic() - started) * 1000)}
            if not data:
                return {
                    "error": "not_found",
                    "symbol": symbol,
                    "source": "swap.coffee",
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                }
            return {"data": data[0], "elapsed_ms": int((time.monotonic() - started) * 1000)}
    except urllib.error.HTTPError as e:
        return {
            "error": "unavailable",
            "reason": "http_error",
            "status_code": e.code,
            "response_snippet": (e.read().decode("utf-8", errors="ignore")[:200] if hasattr(e, "read") else ""),
            "elapsed_ms": int((time.monotonic() - started) * 1000),
            "source": "swap.coffee",
        }
    except urllib.error.URLError:
        return {
            "error": "unavailable",
            "reason": "connection",
            "elapsed_ms": int((time.monotonic() - started) * 1000),
            "source": "swap.coffee",
        }
    except Exception:
        return {
            "error": "unavailable",
            "reason": "unknown",
            "elapsed_ms": int((time.monotonic() - started) * 1000),
            "source": "swap.coffee",
        }

def _normalize_symbol(symbol: str) -> str:
    if symbol is None:
        return ""
    cleaned = symbol.replace("$", "").replace(" ", "").strip()
    return cleaned.upper()

def fetch_token_by_symbol(symbol: str) -> Dict[str, Any]:
    qs = urllib.parse.urlencode({"search": symbol, "size": 10, "verification": TOKENS_VERIFICATION})
    url = f"{SWAP_COFFEE_BASE_URL}/api/v3/jettons?{qs}"
    started = time.monotonic()
    try:
        req = urllib.request.Request(url)
        if COFFEE_KEY:
            req.add_header("X-Api-Key", COFFEE_KEY)
        with urllib.request.urlopen(req, timeout=10) as resp:
            status = getattr(resp, "status", 200)
            body = resp.read().decode("utf-8", errors="ignore")
            if status != 200:
                return {
                    "error": "unavailable",
                    "reason": "non_200",
                    "status_code": status,
                    "response_snippet": body[:200],
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                    "source": "swap.coffee",
                }
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                return {
                    "error": "unavailable",
                    "reason": "json_parse",
                    "status_code": status,
                    "response_snippet": body[:200],
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                    "source": "swap.coffee",
                }
            if not isinstance(data, list):
                return {
                    "error": "unavailable",
                    "reason": "unexpected_payload",
                    "status_code": status,
                    "response_snippet": body[:200],
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                    "source": "swap.coffee",
                }
            for item in data:
                if str(item.get("symbol", "")).upper() == symbol:
                    return {"data": item, "elapsed_ms": int((time.monotonic() - started) * 1000)}
            if not data:
                return {
                    "error": "not_found",
                    "symbol": symbol,
                    "source": "swap.coffee",
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                }
            return {"data": data[0], "elapsed_ms": int((time.monotonic() - started) * 1000)}
    except urllib.error.HTTPError as e:
        return {
            "error": "unavailable",
            "reason": "http_error",
            "status_code": e.code,
            "response_snippet": (e.read().decode("utf-8", errors="ignore")[:200] if hasattr(e, "read") else ""),
            "elapsed_ms": int((time.monotonic() - started) * 1000),
            "source": "swap.coffee",
        }
    except urllib.error.URLError:
        return {
            "error": "unavailable",
            "reason": "connection",
            "elapsed_ms": int((time.monotonic() - started) * 1000),
            "source": "swap.coffee",
        }
    except Exception:
        return {
            "error": "unavailable",
            "reason": "unknown",
            "elapsed_ms": int((time.monotonic() - started) * 1000),
            "source": "swap.coffee",
        }

def _normalize_symbol(symbol: str) -> str:
    if symbol is None:
        return ""
    cleaned = symbol.replace("$", "").replace(" ", "").strip()
    return cleaned.upper()

def _verification_values() -> List[str]:
    parts = [p.strip() for p in TOKENS_VERIFICATION.split(",")]
    return [p for p in parts if p]

def fetch_token_by_symbol(symbol: str) -> Dict[str, Any]:
    params = {
        "search": symbol,
        "size": 10,
        "verification": _verification_values(),
    }
    qs = urllib.parse.urlencode(params, doseq=True)
    url = f"{SWAP_COFFEE_BASE_URL}/api/v3/jettons?{qs}"
    started = time.monotonic()
    try:
        req = urllib.request.Request(url)
        if COFFEE_KEY:
            req.add_header("X-Api-Key", COFFEE_KEY)
        with urllib.request.urlopen(req, timeout=10) as resp:
            status = getattr(resp, "status", 200)
            body = resp.read().decode("utf-8", errors="ignore")
            if status != 200:
                return {
                    "error": "unavailable",
                    "reason": "non_200",
                    "status_code": status,
                    "response_snippet": body[:200],
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                    "source": "swap.coffee",
                }
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                return {
                    "error": "unavailable",
                    "reason": "json_parse",
                    "status_code": status,
                    "response_snippet": body[:200],
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                    "source": "swap.coffee",
                }
            if not isinstance(data, list):
                return {
                    "error": "unavailable",
                    "reason": "unexpected_payload",
                    "status_code": status,
                    "response_snippet": body[:200],
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                    "source": "swap.coffee",
                }
            for item in data:
                if str(item.get("symbol", "")).upper() == symbol:
                    return {"data": item, "elapsed_ms": int((time.monotonic() - started) * 1000)}
            if not data:
                return {
                    "error": "not_found",
                    "symbol": symbol,
                    "source": "swap.coffee",
                    "elapsed_ms": int((time.monotonic() - started) * 1000),
                }
            return {"data": data[0], "elapsed_ms": int((time.monotonic() - started) * 1000)}
    except urllib.error.HTTPError as e:
        return {
            "error": "unavailable",
            "reason": "http_error",
            "status_code": e.code,
            "response_snippet": (e.read().decode("utf-8", errors="ignore")[:200] if hasattr(e, "read") else ""),
            "elapsed_ms": int((time.monotonic() - started) * 1000),
            "source": "swap.coffee",
        }
    except urllib.error.URLError:
        return {
            "error": "unavailable",
            "reason": "connection",
            "elapsed_ms": int((time.monotonic() - started) * 1000),
            "source": "swap.coffee",
        }
    except Exception:
        return {
            "error": "unavailable",
            "reason": "unknown",
            "elapsed_ms": int((time.monotonic() - started) * 1000),
            "source": "swap.coffee",
        }

class IngestDoc(BaseModel):
    text: str
    source: Optional[str] = None

class IngestRequest(BaseModel):
    documents: List[IngestDoc]

class QueryRequest(BaseModel):
    query: str
    top_k: int = 5

class Project(BaseModel):
    id: str
    name: str
    slug: str
    description: Optional[str] = None
    tags: List[str] = []
    official_links: Dict[str, str] = {}
    sources: List[Dict[str, str]] = []
    updated_at: Optional[str] = None

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.get("/projects")
async def list_projects(api_key: str = Depends(verify_inner_calls_key)):
    return load_projects()

@app.get("/projects/{project_id}")
async def get_project(project_id: str, api_key: str = Depends(verify_inner_calls_key)):
    for p in load_projects():
        if p["id"] == project_id:
            return p
    return {"error": "not found"}

@app.get("/tokens/{symbol}")
async def get_token(symbol: str, api_key: str = Depends(verify_inner_calls_key)):
    now = datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
    normalized = _normalize_symbol(symbol)
    source_params = {
        "search": normalized,
        "verification": _verification_values(),
    }
    source_url = f"{SWAP_COFFEE_BASE_URL}/api/v3/jettons?{urllib.parse.urlencode(source_params, doseq=True)}"
    source_url = f"{SWAP_COFFEE_BASE_URL}/api/v3/jettons?search={urllib.parse.quote(normalized)}"

    if not normalized or not (2 <= len(normalized) <= 10):
        return {
            "error": "unavailable",
            "updated_at": now,
            "sources": [
                {
                    "source_name": "tokens.swap.coffee",
                    "source_url": source_url,
                    "fetched_at": now,
                }
            ],
        }

    if normalized == "TON":
        return {
            "id": "TON",
            "type": "native",
            "symbol": "TON",
            "name": "Toncoin",
            "decimals": 9,
            "total_supply": None,
            "holders": None,
            "tx_24h": None,
            "last_activity": None,
            "sources": [
                {
                    "source_name": "ton.org",
                    "source_url": "https://ton.org",
                    "fetched_at": now,
                },
                {
                    "source_name": "docs.ton.org",
                    "source_url": "https://docs.ton.org",
                    "fetched_at": now,
                },
            ],
            "updated_at": now,
        }

    result = fetch_token_by_symbol(normalized)
    if isinstance(result, dict) and result.get("error"):
        return {
            "error": result.get("error") or "unavailable",
            "reason": result.get("reason"),
            "symbol": normalized,
            "status_code": result.get("status_code"),
            "response_snippet": result.get("response_snippet"),
            "elapsed_ms": result.get("elapsed_ms"),
            "updated_at": now,
            "sources": [
                {
                    "source_name": "tokens.swap.coffee",
                    "source_url": source_url,
                    "fetched_at": now,
                }
            ],
        }

    data = result.get("data") if isinstance(result, dict) else None
    if not data or not isinstance(data, dict):
        return {
            "error": "unavailable",
            "symbol": normalized,
            "updated_at": now,
            "sources": [
                {
                    "source_name": "tokens.swap.coffee",
                    "source_url": source_url,
                    "fetched_at": now,
                }
            ],
        }

    stats = data.get("market_stats", {}) if isinstance(data.get("market_stats"), dict) else {}
    metadata = data.get("metadata") if isinstance(data.get("metadata"), dict) else {}
    description = _first_non_none(
        data.get("description"),
        metadata.get("description"),
        data.get("about"),
        data.get("summary"),
    )
    token = {
        "id": data.get("address"),
        "type": "jetton",
        "symbol": data.get("symbol") or normalized,
        "name": data.get("name"),
        "description": description,
        "decimals": _first_non_none(
            data.get("decimals"), metadata.get("decimals")
        ),
        "verified": _first_non_none(
            data.get("verification"),
            metadata.get("verification"),
            data.get("verified"),
            data.get("is_verified"),
        ),
        # Keep source values as-is; do not fabricate fallback numbers.
        "total_supply": _first_non_none(
            data.get("total_supply"), data.get("supply"), data.get("totalSupply")
        ),
        "holders": _first_non_none(
            stats.get("holders_count"), data.get("holders"), data.get("holders_count")
        ),
        "tx_24h": _first_non_none(
            data.get("tx_24h"), data.get("tx24h"), data.get("transactions_24h")
        ),
        "last_activity": _first_non_none(
            data.get("last_activity"), data.get("last_trade_at"), data.get("created_at")
        ),
        "sources": [
            {
                "source_name": "tokens.swap.coffee",
                "source_url": source_url,
                "fetched_at": now,
            }
        ],
        "updated_at": now,
    }

    return token

@app.post("/ingest")
async def ingest(req: IngestRequest, api_key: str = Depends(verify_inner_calls_key)):
    store = load_store()
    for d in req.documents:
        store.append({"text": d.text, "source": d.source or "unknown"})
    save_store(store)
    return {"ingested": len(req.documents), "total": len(store)}

@app.post("/query")
async def query(req: QueryRequest, api_key: str = Depends(verify_inner_calls_key)):
    store = load_store()
    q = req.query.lower().strip()
    q_words = set([w for w in q.split() if len(w) > 2])

    scored = []
    for item in store:
        text = item.get("text", "")
        t = text.lower()
        overlap = sum(1 for w in q_words if w in t)
        if overlap > 0:
            scored.append((overlap, item))

    scored.sort(key=lambda x: x[0], reverse=True)
    top = [x[1] for x in scored[: req.top_k]]

    # Return small snippets to keep responses light
    context = []
    sources = []
    for item in top:
        snippet = item["text"][:800]
        context.append(snippet)
        sources.append(item.get("source", "unknown"))

    # If no doc hits, try lightweight project matching
    if len(top) == 0 and q_words:
        projects = load_projects()
        proj_scored = []
        for p in projects:
            name = str(p.get("name", ""))
            desc = str(p.get("description", ""))
            tags = p.get("tags", [])
            tag_text = " ".join([str(t) for t in tags]) if isinstance(tags, list) else ""
            haystack = f"{name} {desc} {tag_text}".lower()
            overlap = sum(1 for w in q_words if w in haystack)
            if overlap > 0:
                proj_scored.append((overlap, p))

        proj_scored.sort(key=lambda x: x[0], reverse=True)
        top_projects = [x[1] for x in proj_scored[: req.top_k]]

        for p in top_projects:
            name = p.get("name", "Unknown project")
            desc = p.get("description") or ""
            tags = p.get("tags") or []
            tag_text = ", ".join([str(t) for t in tags]) if isinstance(tags, list) else ""
            snippet_parts = [str(name)]
            if desc:
                snippet_parts.append(f"- {desc}")
            if tag_text:
                snippet_parts.append(f"(tags: {tag_text})")
            context.append(" ".join(snippet_parts)[:800])

            source_name = "allowlist"
            proj_sources = p.get("sources")
            if isinstance(proj_sources, list) and proj_sources:
                source_name = proj_sources[0].get("source_name", source_name)
            sources.append({
                "source_name": source_name,
                "project_id": p.get("id"),
                "official_links": p.get("official_links", {}),
            })

    return {"context": context, "sources": sources}

@app.post("/ingest/projects")
async def ingest_projects(projects: List[Project], api_key: str = Depends(verify_inner_calls_key)):
    store = load_projects()
    by_id = {p["id"]: p for p in store}

    for p in projects:
        by_id[p.id] = p.dict()

    merged = list(by_id.values())
    save_projects(merged)
    return {"ingested": len(projects), "total": len(merged)}

@app.post("/ingest/source/allowlist")
async def ingest_allowlist(api_key: str = Depends(verify_inner_calls_key)):
    try:
        if not ALLOWLIST_PATH.exists():
            return {
                "error": "allowlist file not found",
                "path": str(ALLOWLIST_PATH)
            }

        raw = json.loads(ALLOWLIST_PATH.read_text(encoding="utf-8"))

        if not isinstance(raw, list):
            return {"error": "allowlist must be a list"}

        projects = [Project(**p) for p in raw]

        store = load_projects()
        by_id = {p["id"]: p for p in store}

        for p in projects:
            by_id[p.id] = p.dict()

        merged = list(by_id.values())
        save_projects(merged)

        return {
            "source": "allowlist",
            "ingested": len(projects),
            "total": len(merged)
        }

    except Exception as e:
        # critical: NEVER crash
        return {
            "error": "failed to ingest allowlist",
            "detail": str(e)
        }
