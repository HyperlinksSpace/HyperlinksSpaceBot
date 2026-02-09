#!/bin/bash

# Start Ollama in the background
echo "Starting Ollama server..."
# Find Ollama binary - check common locations
if [ -f "/usr/local/bin/ollama" ]; then
    OLLAMA_BIN="/usr/local/bin/ollama"
elif [ -f "/usr/local/lib/ollama" ]; then
    OLLAMA_BIN="/usr/local/lib/ollama"
elif [ -d "/usr/local/lib/ollama" ] && [ -f "/usr/local/lib/ollama/ollama" ]; then
    OLLAMA_BIN="/usr/local/lib/ollama/ollama"
else
    # Try to find it in PATH or via find
    OLLAMA_BIN=$(which ollama 2>/dev/null || find /usr/local -name ollama -type f 2>/dev/null | head -1)
fi

if [ -z "$OLLAMA_BIN" ] || [ ! -f "$OLLAMA_BIN" ]; then
    echo "ERROR: Ollama binary not found! Please check installation."
    exit 1
fi
echo "Found Ollama at: $OLLAMA_BIN"
$OLLAMA_BIN serve > /tmp/ollama.log 2>&1 &
OLLAMA_PID=$!

# Wait for Ollama to be ready (check if it's responding)
echo "Waiting for Ollama to start..."
OLLAMA_READY=false
for i in {1..60}; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "Ollama is ready!"
        OLLAMA_READY=true
        break
    fi
    sleep 1
done

if [ "$OLLAMA_READY" = false ]; then
    echo "Warning: Ollama did not start in time, but continuing with FastAPI..."
    echo "Ollama logs:"
    cat /tmp/ollama.log || true
fi

# Check if model exists, if not pull it in background (don't block startup)
# Model can be set via OLLAMA_MODEL env var, defaults to llama3.2:3b
MODEL=${OLLAMA_MODEL:-llama3.2:3b}
echo "Checking for model: $MODEL"
if [ -n "$OLLAMA_BIN" ] && [ -f "$OLLAMA_BIN" ]; then
    if ! $OLLAMA_BIN list 2>/dev/null | grep -q "$MODEL"; then
        echo "Model $MODEL not found. Will pull in background (this may take a while, ~2GB download)..."
        # Pull model in background so it doesn't block FastAPI startup
        ($OLLAMA_BIN pull $MODEL && echo "Model $MODEL pulled successfully!") || {
            echo "Warning: Failed to pull model. Chat requests will fail until model is available."
        } &
    else
        echo "Model $MODEL already exists"
    fi
else
    echo "Warning: ollama binary not found"
fi

# Start FastAPI app (this is the main process)
echo "Starting FastAPI application on port ${PORT:-8000}..."
cd backend
exec python -m uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}

