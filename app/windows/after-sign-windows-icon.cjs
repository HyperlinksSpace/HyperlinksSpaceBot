/**
 * electron-builder afterSign (Windows): embed icon via app-builder rcedit (see embed-windows-exe-icon.cjs).
 */
const { embedWindowsExeIcon } = require("./embed-windows-exe-icon.cjs");

module.exports = async (context) => {
  if (context.electronPlatformName !== "win32") return;
  await embedWindowsExeIcon({
    appOutDir: context.appOutDir,
    projectDir: context.packager.projectDir,
    productFilename: context.packager.appInfo.productFilename,
  });
};
