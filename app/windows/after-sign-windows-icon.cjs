/**
 * electron-builder afterSign (Windows): re-apply the source .ico to the app exe with node-rcedit.
 *
 * Builder's icon pipeline can emit an ICO that still decodes for createFromPath(file) but leaves the
 * exe's RT_ICON resources in a state where nativeImage.createFromPath(exe) is empty (taskbar / shell).
 * Applying the original assets/icon.ico last fixes that for typical unsigned builds.
 *
 * If you use Authenticode (CSC_LINK / WIN_CSC_LINK), this hook is skipped — re-applying the icon
 * after signing would invalidate the signature; rely on win.icon + signing only in that case.
 */
const fs = require("fs");
const path = require("path");
const rcedit = require("rcedit");

module.exports = async (context) => {
  if (context.electronPlatformName !== "win32") return;

  if (process.env.CSC_LINK || process.env.WIN_CSC_LINK) {
    console.log("[after-sign-windows-icon] skip: CSC_LINK / WIN_CSC_LINK set (would break signature)");
    return;
  }

  const { appOutDir, packager } = context;
  const exeName = `${packager.appInfo.productFilename}.exe`;
  const exe = path.join(appOutDir, exeName);
  const icon = path.join(packager.projectDir, "assets", "icon.ico");

  if (!fs.existsSync(exe)) {
    console.warn(`[after-sign-windows-icon] skip: exe not found: ${exe}`);
    return;
  }
  if (!fs.existsSync(icon)) {
    console.warn(`[after-sign-windows-icon] skip: icon not found: ${icon}`);
    return;
  }

  await new Promise((resolve, reject) => {
    rcedit(exe, { icon }, (err) => (err ? reject(err) : resolve()));
  });
  console.log(`[after-sign-windows-icon] set exe icon from ${icon} → ${exe}`);
};
