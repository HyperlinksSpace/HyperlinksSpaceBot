#!/usr/bin/env python3
"""
Generate favicon.ico from an SVG (e.g. app logo).
Uses svglib + reportlab to render SVG (no native cairo). PIL to build ICO.
Install: pip install svglib reportlab Pillow
"""
import io
import struct
import sys
from pathlib import Path

try:
    from svglib.svglib import svg2rlg
    from reportlab.graphics import renderPM
except ImportError:
    print("Install: pip install svglib reportlab")
    sys.exit(1)
try:
    from PIL import Image
except ImportError:
    print("Install Pillow: pip install Pillow")
    sys.exit(1)

# Favicon sizes (browsers use 16, 32; some use 48)
FAVICON_SIZES = [16, 32, 48]


def svg_to_png_bytes(svg_path: Path, size: int) -> bytes:
    """Render SVG to PNG bytes at given size (square)."""
    drawing = svg2rlg(str(svg_path))
    if drawing is None:
        raise ValueError(f"Could not parse SVG: {svg_path}")
    scale = size / max(drawing.width, drawing.height)
    drawing.width = size
    drawing.height = size
    drawing.scale(scale, scale)
    out = io.BytesIO()
    renderPM.drawToFile(drawing, out, fmt="PNG", dpi=96)
    out.seek(0)
    img = Image.open(out).convert("RGBA")
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    png_out = io.BytesIO()
    img.save(png_out, format="PNG")
    return png_out.getvalue()


def create_ico(png_bytes_list: list[bytes], sizes: list[int], output_path: Path) -> None:
    """Write multi-size ICO file (header + directory + PNG payloads)."""
    ico = bytearray()
    # ICONDIR
    ico += struct.pack("<HHH", 0, 1, len(sizes))
    offset = 6 + 16 * len(sizes)
    for size, png_data in zip(sizes, png_bytes_list):
        w = size if size < 256 else 0
        h = size if size < 256 else 0
        ico += struct.pack(
            "<BBBBHHII",
            w, h, 0, 0, 1, 32, len(png_data), offset
        )
        offset += len(png_data)
    for png_data in png_bytes_list:
        ico += png_data
    output_path.write_bytes(ico)


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    svg_path = repo_root / "assets" / "images" / "loga.svg"
    ico_path = repo_root / "assets" / "favicon.ico"

    if len(sys.argv) >= 2:
        svg_path = Path(sys.argv[1])
    if len(sys.argv) >= 3:
        ico_path = Path(sys.argv[2])

    if not svg_path.exists():
        print(f"SVG not found: {svg_path}")
        sys.exit(1)

    png_list = []
    for s in FAVICON_SIZES:
        png_list.append(svg_to_png_bytes(svg_path, s))
    create_ico(png_list, FAVICON_SIZES, ico_path)
    print(f"Created {ico_path} (sizes: {FAVICON_SIZES})")


if __name__ == "__main__":
    main()
