# Image Generator & Scanner API

Simple API service to **generate images** and **scan/screen images** (use images as carriers of data instead of QR codes). Useful for visual tokens, referral cards, or any flow where you want “show this image” instead of “show this QR code.”

---

## What this service does

| Capability | Description |
|------------|-------------|
| **Generate** | Create an image from a text prompt (and optional payload). The image can encode a small payload (e.g. user id, link) so it can be read back later. |
| **Scan / Screen** | Accept an uploaded image and either (a) **decode** a payload embedded in the image (image-as-code), or (b) **recognize** the image (e.g. match to a known set, or describe it). |

So: **generate** = “make a picture that carries data”; **scan** = “read data from a picture” (instead of scanning a QR code).

---

## API (target design)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness check. |
| POST | `/generate` | Generate an image. Body: `{ "prompt": "...", "payload": "<optional string to embed>" }`. Returns image (e.g. PNG) or URL. |
| POST | `/scan` | Screen an image. Body: multipart form with `file` = image. Returns `{ "payload": "...", "matched": true/false }` or similar. |

Exact request/response fields can be adjusted once you choose an implementation (e.g. add `model`, `size`, `format`).

---

## How to build it: open-source vs self-made models

You can implement the backend with **open-source models** (run yourself or via APIs) or with **self-made / custom models**. Below are concrete options.

---

### 1. Image generation (open-source)

**Option A – Stable Diffusion (local or cloud)**

- **Models:** [Stable Diffusion 1.5](https://huggingface.co/runwayml/stable-diffusion-v1-5), [SDXL](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0), [FLUX](https://huggingface.co/black-forest-labs/FLUX.1-dev) (larger, better quality).
- **Stack:** Python + `diffusers` + `transformers` (PyTorch). Run on GPU (local or cloud VM).
- **Pros:** Full control, no per-image fee, can embed payload in metadata or in the image (e.g. steganography).
- **Cons:** Need GPU and enough RAM; SDXL/FLUX need more resources.

**Option B – Lightweight / small models**

- **Models:** [Stable Diffusion with Tiny AutoEncoder](https://huggingface.co/docs/diffusers/optimization/tiny_vae), or [Kandinsky](https://huggingface.co/kandinsky-community) smaller variants.
- **Stack:** Same `diffusers` pipeline with smaller VAE or smaller checkpoint.
- **Pros:** Lower RAM/VRAM, faster; good for simple or stylized images.
- **Cons:** Quality and diversity lower than SDXL/FLUX.

**Option C – Hosted API (open-source backend)**

- Use a host that runs open-source models: [Replicate](https://replicate.com) (SD, FLUX, etc.), [Together](https://together.ai), or self-hosted [Ollama](https://ollama.com) (for LLaVA-style image gen if you add that path).
- **Pros:** No GPU management; pay per request.
- **Cons:** Depends on provider; you still need to add payload embedding yourself (e.g. in image metadata or stego).

**Embedding a payload in the image (for scan later)**

- **Steganography:** Encode a short string into the image (e.g. [stegano](https://github.com/cedricbonhomme/Stegano), [lsb-steganography](https://github.com/ragibson/Steganography)).
- **Metadata:** Store payload in PNG chunk or EXIF; scanner reads metadata instead of pixels (no ML needed for this part).

---

### 2. Image generation (self-made / custom models)

- **Fine-tuned SD/LoRA:** Train a LoRA (or full fine-tune) on your own style or product images so “generate” matches your look. Use [Hugging Face LoRA training](https://huggingface.co/docs/diffusers/training/lora) or [Kohya](https://github.com/kohya-ss/sd-scripts).
- **Custom small model:** Train a small GAN or diffusion model on a narrow domain (e.g. icons, avatars). Heavier research/dev; only worth it if you need a very specific, constrained output.
- **Pipeline:** Same API: your backend loads your checkpoint/LoRA in `diffusers` and runs the same `POST /generate` endpoint.

---

### 3. Image scanner / screener (open-source)

**Option A – Decode embedded payload (no ML)**

- If you embed payload with **steganography** or **metadata**, the scanner is just: decode from image (stegano library or read EXIF/PNG chunks). No model needed.
- **Stack:** Python + `stegano` or `PIL`/`piexif` for metadata.

**Option B – Recognize / match image (vision model)**

- **Use case:** “Is this one of our generated cards?” or “Which template is this?”
- **Models:** [CLIP](https://github.com/openai/CLIP) (embed image, compare to embeddings of known images), [BLIP](https://huggingface.co/Salesforce/blip2-opt-2.7b) (image captioning for “describe then match”).
- **Stack:** `transformers` + `torch`; compute embedding for uploaded image, compare to stored embeddings of your generated set; return best match + payload stored for that image.

**Option C – Read text / barcode in image**

- If your “image as code” contains text or a barcode: use [Tesseract](https://github.com/tesseract-ocr/tesseract) (OCR) or a barcode library. Scanner = crop → OCR/decode → return payload.

---

### 4. Image scanner (self-made models)

- **Custom classifier:** Train a small CNN (e.g. ResNet, EfficientNet) on your own classes (e.g. “card type A”, “card type B”, “invalid”). Use it in `/scan` to classify and map class → payload.
- **Custom embedding model:** Train a small vision model to embed images in a space where you have a lookup table (id → embedding). Scan = embed upload, nearest-neighbor in table, return id/payload.

---

## Suggested stacks (by resource level)

| Scenario | Generate | Scan |
|----------|----------|------|
| **Minimal (no GPU)** | Hosted API (Replicate/Together) or pre-rendered templates; embed payload in metadata/stegano | Decode stegano/metadata; optional CLIP on CPU (slower). |
| **Single GPU server** | `diffusers` + SD 1.5 or SDXL; stegano or metadata for payload | Same decode; CLIP or small classifier for “match to known image”. |
| **Custom look** | Same GPU + your LoRA/fine-tuned SD | Same scan options; optional custom classifier. |

---

## Repo layout (this folder)

```
imggen/
  README.md           # This file
  backend/
    main.py           # FastAPI app: /health, /generate, /scan
    requirements.txt  # fastapi, uvicorn, image libs, optional torch/diffusers
  data/               # Optional: store generated image index (id → payload, path/embedding)
  requirements.txt    # Top-level deps if needed
  railway.json        # Deploy config (optional)
```

---

## Local run (skeleton)

```bash
cd imggen
pip install -r backend/requirements.txt
uvicorn backend.main:app --reload --port 8002
```

- `GET http://localhost:8002/health` → `{"status":"ok"}`
- `POST /generate` and `POST /scan` are stubs until you plug in a model (see above).

---

## Summary

- **Service:** Simple API to generate images (with optional embedded payload) and to scan images to recover payload or recognize them (instead of QR).
- **Set on Railway:** Same idea as RAG: deploy this service, get a public URL, call it from your app or bot.
- **Open-source:** Use Stable Diffusion (or similar) + steganography/metadata for generate/scan; add CLIP or a small classifier if you need “match to set of images.”
- **Self-made:** Add your own LoRA/fine-tuned model for generation and/or a custom classifier/embedding model for scanning.
