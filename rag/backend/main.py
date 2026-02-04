from fastapi import FastAPI
from pathlib import Path
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import os, json

app = FastAPI()

BASE_DIR = Path(__file__).resolve().parent
ALLOWLIST_PATH = BASE_DIR.parent / "data" / "projects_allowlist.json"

STORE_PATH = os.getenv("RAG_STORE_PATH", "rag_store.json")
PROJECTS_STORE_PATH = os.getenv("PROJECTS_STORE_PATH", "projects_store.json")

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
