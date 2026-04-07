/**
 * Single source of truth for Windows/Electron product naming.
 * Display name and artifact slug come from package.json → build.productName.
 */
const fs = require("fs");
const path = require("path");

const pkgPath = path.join(__dirname, "..", "package.json");
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
const productDisplayName = pkg.build?.productName ?? "Hyperlinks Space Program";
/** No spaces; matches electron-builder artifactName patterns (e.g. HyperlinksSpaceProgram_1.0.0.zip). */
const productSlug = productDisplayName.replace(/\s+/g, "");

/** Previous public name — keep for updater zip matching, staged layouts, and NSIS taskkill of old installs. */
const legacyDisplayNames = ["Hyperlinks Space App"];
const legacySlugs = ["HyperlinksSpaceApp"];

function allKnownExeBaseNames() {
  const set = new Set();
  set.add(`${productDisplayName}.exe`);
  set.add(`${productSlug}.exe`);
  for (const d of legacyDisplayNames) set.add(`${d}.exe`);
  for (const s of legacySlugs) set.add(`${s}.exe`);
  return [...set];
}

/** Regex: release zip assets starting with current or legacy slug (e.g. HyperlinksSpaceProgram_ or HyperlinksSpaceApp_). */
function portableZipAssetPattern() {
  const slugs = [productSlug, ...legacySlugs].join("|");
  return new RegExp(`^(?:${slugs})[_-]`, "i");
}

module.exports = {
  productDisplayName,
  productSlug,
  /** Same as build.win.artifactName portable zip prefix `${slug}_`. */
  portableZipPrefix: `${productSlug}_`,
  legacyDisplayNames,
  legacySlugs,
  allKnownExeBaseNames,
  portableZipAssetPattern,
};
