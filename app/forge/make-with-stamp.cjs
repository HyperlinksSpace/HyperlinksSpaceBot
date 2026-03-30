const { spawn } = require("child_process");
const path = require("path");

function pad2(n) {
  return String(n).padStart(2, "0");
}

function makeBuildStamp(d = new Date()) {
  return `${pad2(d.getMonth() + 1)}${pad2(d.getDate())}${d.getFullYear()}_${pad2(d.getHours())}${pad2(d.getMinutes())}`;
}

function run() {
  const appDir = path.resolve(__dirname, "..");
  const isVerbose = process.argv.includes("--verbose");
  const cliPath = path.join(appDir, "node_modules", "@electron-forge", "cli", "dist", "electron-forge.js");

  const env = {
    ...process.env,
    BUILD_STAMP: process.env.BUILD_STAMP || makeBuildStamp(),
  };

  const args = [cliPath, "make", "--platform", "win32"];
  if (isVerbose) args.push("--verbose");

  console.log(`[forge] BUILD_STAMP=${env.BUILD_STAMP}`);
  console.log(`[forge] node ${args.join(" ")}`);

  const child = spawn(process.execPath, args, {
    cwd: appDir,
    env,
    stdio: "inherit",
    shell: false,
  });

  child.on("close", (code) => process.exit(code || 0));
  child.on("error", () => process.exit(1));
}

run();

