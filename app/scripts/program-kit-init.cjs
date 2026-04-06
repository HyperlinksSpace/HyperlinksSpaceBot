#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const SKIP = new Set(["node_modules", ".git", ".DS_Store"]);

function copyRecursive(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (SKIP.has(entry.name)) continue;
    const from = path.join(src, entry.name);
    const to = path.join(dst, entry.name);
    if (entry.isDirectory()) {
      copyRecursive(from, to);
    } else if (entry.isSymbolicLink()) {
      const real = fs.realpathSync(from);
      const st = fs.statSync(real);
      if (st.isDirectory()) {
        copyRecursive(real, to);
      } else {
        fs.mkdirSync(path.dirname(to), { recursive: true });
        fs.copyFileSync(real, to);
      }
    } else {
      fs.mkdirSync(path.dirname(to), { recursive: true });
      fs.copyFileSync(from, to);
    }
  }
}

function isEmptyDir(dir) {
  try {
    return fs.readdirSync(dir).length === 0;
  } catch (_) {
    return true;
  }
}

const args = process.argv.slice(2);
const force = args.includes("--force");
const targetArg = args.find((a) => !a.startsWith("-")) || ".";
const target = path.resolve(process.cwd(), targetArg);
const packageRoot = path.resolve(__dirname, "..");

if (fs.existsSync(target) && !isEmptyDir(target) && !force) {
  console.error(`Target is not empty: ${target}`);
  console.error("Re-run with --force to overwrite.");
  process.exit(1);
}

fs.mkdirSync(target, { recursive: true });
copyRecursive(packageRoot, target);

console.log(`Program kit scaffold created at ${target}`);
console.log("Next steps:");
console.log(`  cd ${targetArg}`);
console.log("  npm install");
