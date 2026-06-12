"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const packageJson = require("../package.json");

const target = resolveTarget(process.platform, process.arch);
const vendorDir = path.join(__dirname, "..", "vendor", target);
const zypherHome = resolveZypherHome();
const sourceInstallDir = path.join(zypherHome, "source", packageJson.version);

let removedAny = false;

if (fs.existsSync(vendorDir)) {
  fs.rmSync(vendorDir, { recursive: true, force: true });
  console.log(`Removed vendored binary: ${vendorDir}`);
  removedAny = true;
}

if (fs.existsSync(sourceInstallDir)) {
  fs.rmSync(sourceInstallDir, { recursive: true, force: true });
  console.log(`Removed source tree: ${sourceInstallDir}`);
  removedAny = true;
}

const zigVersion = packageJson.zypher && packageJson.zypher.zigVersion;
if (zigVersion) {
  const zigTarget = resolveZigTarget(process.platform, process.arch);
  const zigInstallDir = path.join(zypherHome, "zig", zigVersion, zigTarget);
  if (fs.existsSync(zigInstallDir)) {
    fs.rmSync(zigInstallDir, { recursive: true, force: true });
    console.log(`Removed Zig toolchain: ${zigInstallDir}`);
    removedAny = true;
  }
}

if (!removedAny) {
  console.log("Zypher has already been uninstalled or was not installed via npm.");
}

function resolveTarget(platform, arch) {
  const key = `${platform}-${arch}`;
  const targets = {
    "linux-x64": "x86_64-linux-musl",
    "linux-arm64": "aarch64-linux-musl",
    "darwin-x64": "x86_64-macos",
    "darwin-arm64": "aarch64-macos",
    "win32-x64": "x86_64-windows-gnu",
    "win32-arm64": "aarch64-windows-gnu",
  };
  const t = targets[key];
  if (!t) {
    throw new Error(`Unsupported platform or architecture: ${platform} ${arch}`);
  }
  return t;
}

function resolveZigTarget(platform, arch) {
  const key = `${platform}-${arch}`;
  const targets = {
    "linux-x64": "x86_64-linux",
    "linux-arm64": "aarch64-linux",
    "darwin-x64": "x86_64-macos",
    "darwin-arm64": "aarch64-macos",
    "win32-x64": "x86_64-windows",
    "win32-arm64": "aarch64-windows",
  };
  const t = targets[key];
  if (!t) {
    throw new Error(`Unsupported platform or architecture for Zig: ${platform} ${arch}`);
  }
  return t;
}

function resolveZypherHome() {
  if (process.env.ZYPHER_HOME) {
    return process.env.ZYPHER_HOME;
  }

  const sudoUser = process.env.SUDO_USER;
  if (process.platform !== "win32" && sudoUser && sudoUser !== "root" && isRoot()) {
    const sudoHome = homeForUser(sudoUser);
    if (sudoHome) {
      return path.join(sudoHome, ".zypher");
    }
  }

  return path.join(os.homedir(), ".zypher");
}

function isRoot() {
  return typeof process.getuid === "function" && process.getuid() === 0;
}

function homeForUser(username) {
  try {
    const passwd = fs.readFileSync("/etc/passwd", "utf8");
    for (const line of passwd.split("\n")) {
      const fields = line.split(":");
      if (fields[0] === username && fields[5]) {
        return fields[5];
      }
    }
  } catch (_) {}
  return null;
}
