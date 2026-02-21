# OpenAI Connection and Slim Build (No Ollama)

This document describes how to use **OpenAI** via the **OPENAI_SWITCH** and **OPENAI_KEY** env vars, and how to build a **slim image** when **OLLAMA_SWITCH=0** so the image does not include Ollama and stays under Railway’s 4 GB limit.

---

## 1. Overview

| Goal | How |
|------|-----|
| **Use OpenAI** | Set `OPENAI_SWITCH=1` and `OPENAI_KEY` (and optionally `OPENAI_MODEL`; default `gpt-4o`). |
| **Prevent Ollama at runtime** | Set `OLLAMA_SWITCH=0`. `start.sh` will not start Ollama or run `ollama pull`. |
| **Prevent Ollama in the image** | Build with `INCLUDE_OLLAMA=0` or use `Dockerfile.slim`. No Ollama binary in the image. |

Defaults: **OLLAMA_SWITCH=1**, **OPENAI_SWITCH=0** (local). On server: **OLLAMA_SWITCH=0**, **OPENAI_SWITCH=1**, **OPENAI_KEY** set.

---

## 2. Runtime switches

- **OLLAMA_SWITCH** – default `1`. When `1`, Ollama is started and the model is pulled at container start (if the image includes Ollama). When `0`, Ollama is never started and no model is downloaded.
- **OPENAI_SWITCH** – default `0`. When `1` and **OPENAI_KEY** is set, OpenAI is the **primary** LLM. If **OLLAMA_SWITCH=1** as well, Ollama is used as **fallback** if OpenAI fails or does not respond.
- **OPENAI_KEY** – OpenAI API key (canonical name; `OPENAI_API_KEY` still accepted). Required when `OPENAI_SWITCH=1`.
- **OPENAI_MODEL** – default **gpt-4o** (no need to set on server if using this model).

### Example: local (Ollama primary)

```bash
OLLAMA_SWITCH=1
OPENAI_SWITCH=0
```

### Example: server (OpenAI only, no Ollama)

```bash
OLLAMA_SWITCH=0
OPENAI_SWITCH=1
OPENAI_KEY=sk-...
# OPENAI_MODEL=gpt-4o is default
```

### Example: local (OpenAI primary, Ollama fallback)

```bash
OLLAMA_SWITCH=1
OPENAI_SWITCH=1
OPENAI_KEY=sk-...
```

---

## 3. Build-time switch: slim image (no Ollama in the image)

When **OLLAMA_SWITCH=0** on the server, you should **not** include Ollama in the image to save space (and stay under 4 GB on Railway).

### Automatic on Railway

The Dockerfile declares **ARG OLLAMA_SWITCH=1**. Railway passes your **Variables** as Docker build args when the variable is declared. So if you set **OLLAMA_SWITCH=0** in the AI service’s Variables (for runtime), Railway will also pass **OLLAMA_SWITCH=0** at build time → the image is built **without** Ollama (slim) automatically. No extra build config needed.

### Manual: build arg with main Dockerfile

```bash
# Use same variable as runtime (recommended)
docker build --build-arg OLLAMA_SWITCH=0 -t ai-slim ./ai

# Or use the alias
docker build --build-arg INCLUDE_OLLAMA=0 -t ai-slim ./ai
```

- **OLLAMA_SWITCH=1** or unset (default): image includes Ollama (~4+ GB).
- **OLLAMA_SWITCH=0** (or **INCLUDE_OLLAMA=0**): slim image, no Ollama (~250–350 MB).

### Option: Dockerfile.slim

```bash
docker build -f ai/Dockerfile.slim -t ai-slim ./ai
```

This image never contains Ollama. Use it when you don’t want to pass build args.

---

## 4. Checklist: OpenAI on server, no Ollama download

- [ ] **Runtime**
  - Set `OLLAMA_SWITCH=0`.
  - Set `OPENAI_SWITCH=1`.
  - Set `OPENAI_KEY`.
  - Optionally set `OPENAI_MODEL` (default: `gpt-4o`).
- [ ] **Build (to stay under 4 GB)**
  - Build with `INCLUDE_OLLAMA=0`, or use `Dockerfile.slim`.
- [ ] **Deploy**
  - Deploy the slim image and set the variables above.

---

## 5. Switching back to Ollama

- Set **OLLAMA_SWITCH=1** (and optionally **OLLAMA_URL**, **OLLAMA_MODEL**).
- Use an image that includes Ollama (default Dockerfile with **INCLUDE_OLLAMA=1** or no build arg). The model is pulled at container start when needed.

---

## 6. Summary

| What | How |
|------|-----|
| Use OpenAI | `OPENAI_SWITCH=1` + `OPENAI_KEY` (+ optional `OPENAI_MODEL`; default `gpt-4o`). |
| No Ollama at runtime | `OLLAMA_SWITCH=0`. |
| No Ollama model download | Same: `OLLAMA_SWITCH=0`. |
| No Ollama in image (slim, &lt;4 GB) | Build with `INCLUDE_OLLAMA=0` or `Dockerfile.slim`. |
