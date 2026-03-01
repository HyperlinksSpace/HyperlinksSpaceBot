from __future__ import annotations

from contextlib import asynccontextmanager

import httpx

try:
    from app.config import get_ai_backend_url
except ModuleNotFoundError:
    from bot.app.config import get_ai_backend_url


async def post_chat_once(messages: list, api_key: str, timeout_s: float) -> tuple[int, str, str]:
    """Send non-stream chat request to AI backend."""
    ai_backend_url = get_ai_backend_url()
    upstream_body = {"messages": messages, "stream": False}
    async with httpx.AsyncClient(timeout=timeout_s) as client:
        upstream = await client.post(
            f"{ai_backend_url}/api/chat",
            json=upstream_body,
            headers={
                "Content-Type": "application/json",
                "X-API-Key": api_key,
            },
        )
    content_type = upstream.headers.get("content-type", "application/x-ndjson")
    return upstream.status_code, upstream.text, content_type


@asynccontextmanager
async def stream_chat(messages: list, api_key: str, timeout_s: float = 60.0):
    """Open streaming chat connection to AI backend."""
    ai_backend_url = get_ai_backend_url()
    async with httpx.AsyncClient(timeout=timeout_s) as client:
        async with client.stream(
            "POST",
            f"{ai_backend_url}/api/chat",
            json={"messages": messages},
            headers={
                "Content-Type": "application/json",
                "X-API-Key": api_key,
            },
        ) as response:
            yield ai_backend_url, response
