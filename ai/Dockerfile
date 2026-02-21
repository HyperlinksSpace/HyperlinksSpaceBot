FROM python:3.11-slim

WORKDIR /app

# Build arg: 0 = slim image (no Ollama). Railway passes Variables as build args when ARG is declared.
# Set OLLAMA_SWITCH=0 in Railway Variables → same var drives both build (slim image) and runtime (no Ollama start).
ARG OLLAMA_SWITCH=1
# Alias for explicit control: --build-arg INCLUDE_OLLAMA=0
ARG INCLUDE_OLLAMA

# Install system deps only when including Ollama (OLLAMA_SWITCH=0 or INCLUDE_OLLAMA=0 → skip)
RUN _skip_ollama=0; \
    if [ "$OLLAMA_SWITCH" = "0" ] || [ "$OLLAMA_SWITCH" = "false" ]; then _skip_ollama=1; fi; \
    if [ "$INCLUDE_OLLAMA" = "0" ]; then _skip_ollama=1; fi; \
    if [ "$_skip_ollama" = "1" ]; then echo "Ollama not installed (slim image)"; exit 0; fi; \
    apt-get update && apt-get install -y curl zstd && rm -rf /var/lib/apt/lists/*
RUN _skip_ollama=0; \
    if [ "$OLLAMA_SWITCH" = "0" ] || [ "$OLLAMA_SWITCH" = "false" ]; then _skip_ollama=1; fi; \
    if [ "$INCLUDE_OLLAMA" = "0" ]; then _skip_ollama=1; fi; \
    if [ "$_skip_ollama" = "1" ]; then exit 0; fi; \
    set -e && \
    curl -fsSL https://ollama.com/install.sh -o /tmp/install-ollama.sh && \
    chmod +x /tmp/install-ollama.sh && \
    /tmp/install-ollama.sh && \
    rm /tmp/install-ollama.sh && \
    echo "Ollama installation completed"

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend code
COPY backend/ ./backend/

# Copy start script
COPY start.sh ./
RUN sed -i 's/\r$//' start.sh && chmod +x start.sh

# Expose ports
# 8000 for FastAPI, 11434 for Ollama (internal only)
EXPOSE 8000

# Run start script which starts both Ollama and FastAPI
CMD ["./start.sh"]

