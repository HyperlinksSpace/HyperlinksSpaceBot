import importlib
import os

DEFAULT_AI_BACKEND_URL = "http://127.0.0.1:8000"
DEFAULT_HTTP_HOST = "0.0.0.0"
DEFAULT_HTTP_PORT = 8080
APP_URL_CONFIG_HINT = "Set APP_URL to a valid public or local frontend URL."


def load_env() -> None:
    """Load .env if python-dotenv is available."""
    try:
        _dotenv = importlib.import_module("dotenv")
        _load_dotenv = getattr(_dotenv, "load_dotenv", None)
        if callable(_load_dotenv):
            _load_dotenv()
    except ModuleNotFoundError:
        pass


def get_ai_backend_url() -> str:
    return (os.getenv("AI_BACKEND_URL") or DEFAULT_AI_BACKEND_URL).strip().rstrip("/")


def get_api_key() -> str:
    return (os.getenv("SELF_API_KEY") or os.getenv("API_KEY") or "").strip()


def get_http_bind() -> tuple[str, int]:
    host = os.getenv("HTTP_HOST", DEFAULT_HTTP_HOST)
    port = int(os.getenv("PORT", os.getenv("HTTP_PORT", str(DEFAULT_HTTP_PORT))))
    return host, port

