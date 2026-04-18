/**
 * Rasterizes NSIS installer artwork from SVG sources to exact BMP dimensions
 * expected by electron-builder (buildResources = windows/).
 *
 * Pipeline: SVG → Sharp (librsvg) raw RGBA → 24-bit BMP (no PNG intermediate).
 *
 * Sources: assets/images/installerHeader.svg (150×57), installerSidebar.svg (164×314)
 * Outputs: windows/installerHeader.bmp, windows/installerSidebar.bmp
 */
const fs = require("fs");
const path = require("path");
const { encodeBmp24FromRgba } = require("./rgba-to-bmp24.cjs");

let sharp;
try {
  sharp = require("sharp");
} catch {
  console.error(
    "[installer-bmp] sharp is required. Run: npm install (devDependency sharp).",
  );
  process.exit(1);
}

const appDir = path.join(__dirname, "..");

const JOBS = [
  {
    svg: path.join(appDir, "assets", "images", "installerHeader.svg"),
    bmp: path.join(appDir, "windows", "installerHeader.bmp"),
    width: 150,
    height: 57,
  },
  {
    svg: path.join(appDir, "assets", "images", "installerSidebar.svg"),
    bmp: path.join(appDir, "windows", "installerSidebar.bmp"),
    width: 164,
    height: 314,
  },
];

async function rasterizeOne({ svg, bmp, width, height }) {
  if (!fs.existsSync(svg)) {
    throw new Error(`Missing SVG: ${path.relative(appDir, svg)}`);
  }

  const { data, info } = await sharp(svg)
    .resize(width, height, { fit: "fill" })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  if (info.channels !== 4) {
    throw new Error(`Expected RGBA (4 channels), got ${info.channels}`);
  }
  if (info.width !== width || info.height !== height) {
    throw new Error(`Unexpected raster size ${info.width}×${info.height}, want ${width}×${height}`);
  }

  const bmpBuf = encodeBmp24FromRgba(data, width, height);
  fs.writeFileSync(bmp, bmpBuf);

  console.log(
    `[installer-bmp] ${path.relative(appDir, svg)} → ${path.relative(appDir, bmp)} (${width}×${height}, RGBA→BMP24)`,
  );
}

async function main() {
  for (const job of JOBS) {
    await rasterizeOne(job);
  }
}

main().catch((err) => {
  console.error("[installer-bmp] failed:", err.message || err);
  process.exit(1);
});
