from fastapi import FastAPI
from pathlib import Path
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import os, json
from datetime import datetime
import urllib.request
import urllib.error
import urllib.parse

app = FastAPI()

BASE_DIR = Path(__file__).resolve().parent
ALLOWLIST_PATH = BASE_DIR.parent / "data" / "projects_allowlist.json"

STORE_PATH = os.getenv("RAG_STORE_PATH", "rag_store.json")
PROJECTS_STORE_PATH = os.getenv("PROJECTS_STORE_PATH", "projects_store.json")
TOKENS_API_URL = os.getenv("TOKENS_API_URL", "https://tokens.swap.coffee")
TOKENS_STORE_PATH = os.getenv("TOKENS_STORE_PATH", "tokens_store.json")
TOKENS_API_KEY = os.getenv("TOKENS_API_KEY")

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

def load_tokens() -> List[Dict[str, Any]]:
    if not os.path.exists(TOKENS_STORE_PATH):
        return []
    try:
        data = json.loads(open(TOKENS_STORE_PATH, "r", encoding="utf-8").read())
        if isinstance(data, dict):
            return list(data.values())
        if isinstance(data, list):
            return data
        return []
    except:
        return []

def save_tokens(tokens: List[Dict[str, Any]]) -> None:
    with open(TOKENS_STORE_PATH, "w", encoding="utf-8") as f:
        f.write(json.dumps(tokens, ensure_ascii=False, indent=2))

def _safe_int(value: Any) -> Optional[int]:
    try:
        return int(value)
    except:
        return None

def _normalize_symbol(symbol: str) -> str:
    if symbol is None:
        return ""
    cleaned = symbol.replace("$", "").replace(" ", "").strip()
    return cleaned.upper()

def fetch_token_by_symbol(symbol: str) -> Optional[Dict[str, Any]]:
    qs = urllib.parse.urlencode({"search": symbol, "size": 10})
    url = f"{TOKENS_API_URL}/api/v3/jettons?{qs}"
    try:
        req = urllib.request.Request(url)
        if TOKENS_API_KEY:
            req.add_header("X-Api-Key", TOKENS_API_KEY)
        with urllib.request.urlopen(req, timeout=10) as resp:
            if getattr(resp, "status", 200) != 200:
                return None
            payload = resp.read().decode("utf-8")
            data = json.loads(payload)
            if not isinstance(data, list):
                return None
            for item in data:
                if str(item.get("symbol", "")).upper() == symbol:
                    return item
            return data[0] if data else None
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError):
        return None
    except:
        return None

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
async def list_projects():
    return load_projects()

@app.get("/projects/{project_id}")
async def get_project(project_id: str):
    for p in load_projects():
        if p["id"] == project_id:
            return p
    return {"error": "not found"}

@app.get("/tokens/{symbol}")
async def get_token(symbol: str):
    normalized = _normalize_symbol(symbol)
    now = datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
    source_url = f"{TOKENS_API_URL}/api/v3/jettons?search={urllib.parse.quote(normalized)}"

    if not normalized:
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

    cached = load_tokens()
    by_symbol = {str(t.get("symbol", "")).upper(): t for t in cached if isinstance(t, dict)}
    if normalized in by_symbol:
        return by_symbol[normalized]

    data = fetch_token_by_symbol(normalized)
    if not data:
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

    stats = data.get("market_stats", {}) if isinstance(data.get("market_stats"), dict) else {}
    token = {
        "id": data.get("address"),
        "type": "jetton",
        "symbol": data.get("symbol") or normalized,
        "name": data.get("name"),
        "decimals": _safe_int(data.get("decimals")),
        "total_supply": data.get("total_supply") or data.get("supply") or data.get("totalSupply"),
        "holders": _safe_int(
            data.get("holders")
            or data.get("holders_count")
            or stats.get("holders_count")
        ),
        "tx_24h": _safe_int(
            data.get("tx_24h")
            or data.get("tx24h")
            or data.get("transactions_24h")
        ),
        "last_activity": data.get("last_activity")
        or data.get("last_trade_at")
        or data.get("created_at"),
        "sources": [
            {
                "source_name": "tokens.swap.coffee",
                "source_url": source_url,
                "fetched_at": now,
            }
        ],
        "updated_at": now,
    }

    by_symbol[normalized] = token
    save_tokens(list(by_symbol.values()))

    return token

@app.post("/ingest")
async def ingest(req: IngestRequest):
    store = load_store()
    for d in req.documents:
        store.append({"text": d.text, "source": d.source or "unknown"})
    save_store(store)
    return {"ingested": len(req.documents), "total": len(store)}

@app.post("/query")
async def query(req: QueryRequest):
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
async def ingest_projects(projects: List[Project]):
    store = load_projects()
    by_id = {p["id"]: p for p in store}

    for p in projects:
        by_id[p.id] = p.dict()

    merged = list(by_id.values())
    save_projects(merged)
    return {"ingested": len(projects), "total": len(merged)}

@app.post("/ingest/source/allowlist")
async def ingest_allowlist():
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
