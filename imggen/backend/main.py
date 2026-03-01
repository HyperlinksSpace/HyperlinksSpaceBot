"""
Image Generator & Scanner API (skeleton).
- POST /generate: create image from prompt (and optional payload to embed).
- POST /scan: decode payload or recognize image from upload.
Implement generation/scan with open-source or self-made models (see README).
"""
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from typing import Optional
import os

app = FastAPI(title="Image Generator & Scanner API")

# Optional: API key for production
API_KEY = os.getenv("API_KEY")


class GenerateRequest(BaseModel):
    prompt: str
    payload: Optional[str] = None  # Optional string to embed in image (for scan later)
    width: Optional[int] = 512
    height: Optional[int] = 512


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/generate")
async def generate(req: GenerateRequest):
    """
    Generate an image from a text prompt.
    Optionally embed 'payload' in the image (e.g. steganography or metadata) so /scan can recover it.
    Implement with: diffusers (SD/SDXL), Replicate, or your own model.
    """
    # Stub: return a minimal 1x1 PNG or 404 until you plug in a real model
    # When implemented: run your model -> get PIL Image -> encode PNG -> return Response(content=bytes, media_type="image/png")
    raise HTTPException(
        status_code=501,
        detail="Not implemented. Plug in an open-source or self-made model (see README)."
    )


@app.post("/scan")
async def scan(file: UploadFile = File(...)):
    """
    Screen an uploaded image: decode embedded payload or recognize image.
    Use steganography decode, metadata read, or a vision model (CLIP / classifier).
    """
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Expected an image file")
    # Stub: read bytes and return placeholder until you plug in decode/recognition
    # When implemented: decode payload from image (stegano/metadata) or run CLIP/classifier -> return {"payload": "...", "matched": True}
    raise HTTPException(
        status_code=501,
        detail="Not implemented. Plug in steganography decode or vision model (see README)."
    )
