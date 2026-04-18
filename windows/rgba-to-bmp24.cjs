/**
 * Encode raw RGBA (top-down, row-major) as a Windows 24-bit BMP (BI_RGB).
 * Uses negative biHeight so pixel order matches typical raster buffers (top row first).
 */
function encodeBmp24FromRgba(rgba, width, height) {
  if (rgba.length < width * height * 4) {
    throw new Error("RGBA buffer too small for dimensions");
  }
  const stride = Math.floor((width * 3 + 3) / 4) * 4;
  const imageSize = stride * height;
  const headerSize = 14 + 40;
  const fileSize = headerSize + imageSize;
  const buf = Buffer.alloc(fileSize);
  let o = 0;

  buf.write("BM", o);
  o += 2;
  buf.writeUInt32LE(fileSize, o);
  o += 4;
  buf.writeUInt32LE(0, o);
  o += 4;
  buf.writeUInt32LE(headerSize, o);
  o += 4;

  buf.writeUInt32LE(40, o);
  o += 4;
  buf.writeInt32LE(width, o);
  o += 4;
  buf.writeInt32LE(-height, o);
  o += 4;
  buf.writeUInt16LE(1, o);
  o += 2;
  buf.writeUInt16LE(24, o);
  o += 2;
  buf.writeUInt32LE(0, o);
  o += 4;
  buf.writeUInt32LE(imageSize, o);
  o += 4;
  buf.writeInt32LE(0, o);
  o += 4;
  buf.writeInt32LE(0, o);
  o += 4;
  buf.writeUInt32LE(0, o);
  o += 4;
  buf.writeUInt32LE(0, o);
  o += 4;

  for (let y = 0; y < height; y++) {
    const rowStart = headerSize + y * stride;
    let p = rowStart;
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      buf[p++] = rgba[i + 2];
      buf[p++] = rgba[i + 1];
      buf[p++] = rgba[i];
    }
    while (p < rowStart + stride) {
      buf[p++] = 0;
    }
  }

  return buf;
}

module.exports = { encodeBmp24FromRgba };
