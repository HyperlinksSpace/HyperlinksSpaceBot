/**
 * Embed assets/icon.ico into the Windows app .exe using electron-builder's app-builder `rcedit`
 * (same stack as WinPackager.signAndEditResources). Do not use the `rcedit` npm wrapper here:
 * it often lacks bin/rcedit.exe or uses an older binary that mishandles large PNG-based .ico files.
 */
const fs = require("fs");
const path = require("path");
const { executeAppBuilder } = require("builder-util");

async function embedIconWithAppBuilder(exePath, iconPath) {
  const rceditArgs = [exePath, "--set-icon", path.resolve(iconPath)];
  await executeAppBuilder(["rcedit", "--args", JSON.stringify(rceditArgs)], undefined, {}, 3);
}

/**
 * @param {{ appOutDir: string, projectDir: string, productFilename?: string }} opts
 */
async function embedWindowsExeIcon(opts) {
  if (process.platform !== "win32") return;
  if (process.env.CSC_LINK || process.env.WIN_CSC_LINK) {
    console.log("[embed-windows-exe-icon] skip: CSC_LINK / WIN_CSC_LINK set (would break signature)");
    return;
  }
  const icon = path.resolve(opts.projectDir, "assets", "icon.ico");
  if (!fs.existsSync(icon)) {
    console.warn(`[embed-windows-exe-icon] skip: missing ${icon}`);
    return;
  }
  let exe;
  if (opts.productFilename) {
    exe = path.join(opts.appOutDir, `${opts.productFilename}.exe`);
  } else {
    let names;
    try {
      names = fs.readdirSync(opts.appOutDir);
    } catch (e) {
      console.warn(`[embed-windows-exe-icon] skip: cannot read ${opts.appOutDir}: ${e?.message || e}`);
      return;
    }
    const exes = names.filter((f) => f.endsWith(".exe") && !/uninstall/i.test(f));
    if (exes.length !== 1) {
      console.warn(`[embed-windows-exe-icon] skip: expected one app .exe in ${opts.appOutDir}, got: ${exes.join(", ")}`);
      return;
    }
    exe = path.join(opts.appOutDir, exes[0]);
  }
  if (!fs.existsSync(exe)) {
    console.warn(`[embed-windows-exe-icon] skip: exe not found ${exe}`);
    return;
  }
  await embedIconWithAppBuilder(exe, icon);
  console.log(`[embed-windows-exe-icon] app-builder rcedit: ${icon} -> ${exe}`);
}

module.exports = { embedWindowsExeIcon, embedIconWithAppBuilder };
