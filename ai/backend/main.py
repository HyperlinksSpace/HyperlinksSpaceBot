from fastapi import FastAPI, HTTPException, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any, Union, Literal
import httpx
import os
import json

app = FastAPI()

# CORS middleware to allow Flutter app to call this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your Flutter app domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Ollama API URL - defaults to localhost, can be overridden with env var
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
# Using llama3.2:3b as default - multilingual model optimized for 8GB RAM
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2:3b")
RAG_URL = os.getenv("RAG_URL")

# API Key for authentication - must be set in environment variables
API_KEY = os.getenv("API_KEY")
if not API_KEY:
    raise ValueError("API_KEY environment variable must be set for API security")


def verify_api_key(x_api_key: Optional[str] = Header(None, alias="X-API-Key")):
    """
    Verify API key from X-API-Key header
    """
    if not x_api_key:
        raise HTTPException(
            status_code=401,
            detail="API key required. Please provide X-API-Key header."
        )
    if x_api_key != API_KEY:
        raise HTTPException(
            status_code=403,
            detail="Invalid API key"
        )
    return x_api_key


class ChatMessage(BaseModel):
    """Individual chat message following Ollama ChatMessage format"""
    role: Literal["system", "user", "assistant", "tool"] = Field(..., description="Author of the message")
    content: str = Field(..., description="Message text content")
    images: Optional[List[str]] = Field(default=None, description="Optional list of inline images for multimodal models")
    tool_calls: Optional[List[Dict[str, Any]]] = Field(default=None, description="Tool call requests produced by the model")


class ModelOptions(BaseModel):
    """Runtime options that control text generation"""
    seed: Optional[int] = None
    temperature: Optional[float] = None
    top_k: Optional[int] = None
    top_p: Optional[float] = None
    min_p: Optional[float] = None
    stop: Optional[Union[str, List[str]]] = None
    num_ctx: Optional[int] = None
    num_predict: Optional[int] = None
    num_thread: Optional[int] = None  # Custom field for backward compatibility


class ChatRequest(BaseModel):
    """Chat request following Ollama API spec"""
    model: Optional[str] = Field(default=None, description="Model name (uses OLLAMA_MODEL env var if not provided)")
    messages: List[ChatMessage] = Field(..., description="Chat history as an array of message objects")
    tools: Optional[List[Dict[str, Any]]] = Field(default=None, description="Optional list of function tools the model may call")
    format: Optional[Union[str, Dict[str, Any]]] = Field(default=None, description="Format to return a response in. Can be 'json' or a JSON schema")
    options: Optional[ModelOptions] = Field(default=None, description="Runtime options that control text generation")
    stream: bool = Field(default=True, description="Enable streaming response")
    think: Optional[Union[bool, str]] = Field(default=None, description="When true, returns separate thinking output. Can be boolean or 'high', 'medium', 'low'")
    keep_alive: Optional[Union[str, int]] = Field(default=None, description="Model keep-alive duration (e.g., '5m' or 0)")
    logprobs: Optional[bool] = Field(default=None, description="Whether to return log probabilities of the output tokens")
    top_logprobs: Optional[int] = Field(default=None, description="Number of most likely tokens to return at each token position when logprobs are enabled")


@app.get("/")
async def root():
    return {"status": "ok", "message": "AI Chat API is running"}


@app.post("/api/chat")
async def chat(request: ChatRequest, api_key: str = Depends(verify_api_key)):
    """
    Generate a chat message following Ollama API spec
    Requires valid API key in X-API-Key header
    """
    if not request.messages or len(request.messages) == 0:
        raise HTTPException(status_code=400, detail="Messages array cannot be empty")
    
    # Use provided model or fall back to environment variable default
    model = request.model or OLLAMA_MODEL
    
    # Optional RAG grounding (only if RAG_URL is set)
    rag_context = None
    rag_sources = None
    if RAG_URL:
        try:
            user_last = next((m.content for m in reversed(request.messages) if m.role == "user"), "")
            if user_last:
                async with httpx.AsyncClient(timeout=10.0) as client:
                    r = await client.post(f"{RAG_URL}/query", json={"query": user_last, "top_k": 5})
                    if r.status_code == 200:
                        data = r.json()
                        rag_context = data.get("context", [])
                        rag_sources = data.get("sources", [])
        except:
            pass
    
    # Convert ChatMessage objects to dicts for Ollama API
    # According to Ollama API spec, messages must have role and content (both required)
    messages_dict = []
    if rag_context:
        context_block = "\n\n---\n\n".join(rag_context)
        sys_msg = (
            "You are an AI assistant for TON/token analysis.\n"
            "Use ONLY the context below. If the context is insufficient, say you don't have enough data.\n"
            "Avoid hard price predictions; provide scenarios and risks instead.\n\n"
            f"CONTEXT:\n{context_block}"
        )
        messages_dict.append({"role": "system", "content": sys_msg})
    for msg in request.messages:
        msg_dict = {
            "role": msg.role,
            "content": msg.content
        }
        # Add optional fields if present
        if msg.images:
            msg_dict["images"] = msg.images
        if msg.tool_calls:
            msg_dict["tool_calls"] = msg.tool_calls
        messages_dict.append(msg_dict)
    
    # Build request body for Ollama API
    ollama_request = {
        "model": model,
        "messages": messages_dict,
        "stream": request.stream,
    }
    
    # Add optional fields if present
    if request.tools:
        ollama_request["tools"] = request.tools
    if request.format:
        ollama_request["format"] = request.format
    # Handle options - use provided options or defaults for backward compatibility
    if request.options:
        # Convert ModelOptions to dict, excluding None values
        options_dict = request.options.model_dump(exclude_none=True)
        if options_dict:
            ollama_request["options"] = options_dict
    else:
        # Default options for backward compatibility with existing clients
        ollama_request["options"] = {
            "num_predict": 1000,
            "temperature": 0.7,
            "num_thread": 2,
        }
    if request.think is not None:
        ollama_request["think"] = request.think
    if request.keep_alive is not None:
        ollama_request["keep_alive"] = request.keep_alive
    if request.logprobs is not None:
        ollama_request["logprobs"] = request.logprobs
    if request.top_logprobs is not None:
        ollama_request["top_logprobs"] = request.top_logprobs
    
    async def generate_response():
        try:
            # Call Ollama /api/chat endpoint with messages array (according to API spec)
            async with httpx.AsyncClient(timeout=60.0) as client:
                async with client.stream(
                    "POST",
                    f"{OLLAMA_URL}/api/chat",
                    json=ollama_request
                ) as response:
                    if response.status_code != 200:
                        error_detail = "Unknown error"
                        try:
                            error_text = await response.aread()
                            error_data = json.loads(error_text)
                            error_detail = error_data.get("error", str(error_text))
                        except:
                            error_detail = str(response.status_code)
                        
                        yield json.dumps({"error": f"Ollama error: {error_detail}"}) + "\n"
                        return
                    
                    full_response = ""
                    async for line in response.aiter_lines():
                        if line:
                            try:
                                data = json.loads(line)
                                
                                # Ollama /api/chat streaming format: message.content contains partial text
                                # According to ChatStreamEvent spec: message.content is "Partial assistant message text"
                                if "message" in data and isinstance(data["message"], dict):
                                    content = data["message"].get("content", "")
                                    if content:
                                        full_response += content
                                        # Send each content chunk as it arrives
                                        yield json.dumps({"token": content, "done": data.get("done", False)}) + "\n"
                                
                                # Check if stream is done
                                if data.get("done", False):
                                    # Send final complete response
                                    yield json.dumps({"response": full_response, "done": True}) + "\n"
                                    break
                            except json.JSONDecodeError as e:
                                print(f"Warning: Failed to parse JSON line: {line[:100]}")
                                continue
        
        except httpx.TimeoutException:
            yield json.dumps({"error": "Request timeout - AI model took too long to respond"}) + "\n"
        except httpx.RequestError as e:
            yield json.dumps({"error": f"Cannot connect to Ollama at {OLLAMA_URL}. Error: {str(e)}"}) + "\n"
        except Exception as e:
            yield json.dumps({"error": f"Internal server error: {str(e)}"}) + "\n"
    
    return StreamingResponse(generate_response(), media_type="application/x-ndjson")


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)

