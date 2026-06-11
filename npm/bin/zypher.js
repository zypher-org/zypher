#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const packageJson = require("../package.json");

const zigVersion = packageJson.zypher.zigVersion;
const target = resolveTarget(process.platform, process.arch);
const zigTarget = resolveZigTarget(process.platform, process.arch);
const exeName = process.platform === "win32" ? "zypher.exe" : "zypher";
const exePath = path.join(__dirname, "..", "vendor", target, exeName);
const zypherHome = resolveZypherHome();
const zigBinDir = path.join(zypherHome, "zig", zigVersion, zigTarget);
const zypherRoot = process.env.ZYPHER_ROOT || path.join(zypherHome, "source", packageJson.version);

if (!fs.existsSync(exePath)) {
  console.error(`zypher binary is missing for ${target}. Try reinstalling the package.`);
  process.exit(1);
}

const pathKey = resolvePathKey(process.env);
const childEnv = {
  ...process.env,
  [pathKey]: [zigBinDir, process.env[pathKey]].filter(Boolean).join(path.delimiter),
  ZYPHER_ROOT: zypherRoot,
};

const result = spawnSync(exePath, withZypherRoot(process.argv.slice(2)), {
  env: childEnv,
  stdio: "inherit",
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 0);

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

  const target = targets[key];
  if (!target) {
    console.error(`Unsupported platform or architecture: ${platform} ${arch}`);
    process.exit(1);
  }

  return target;
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

  const target = targets[key];
  if (!target) {
    console.error(`Unsupported platform or architecture for Zig: ${platform} ${arch}`);
    process.exit(1);
  }

  return target;
}

function resolvePathKey(env) {
  if (process.platform !== "win32") {
    return "PATH";
  }
  return Object.keys(env).find((key) => key.toLowerCase() === "path") || "Path";
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
  } catch (_) {
    // Fall back to os.homedir() below when /etc/passwd is unavailable.
  }
  return null;
}

function withZypherRoot(args) {
  const command = args[0];
  if (!command || !["run", "doc", "doc-user"].includes(command)) {
    return args;
  }
  if (hasOptionBeforePassthrough(args, "--zypher-root")) {
    return args;
  }
  return [command, "--zypher-root", zypherRoot, ...args.slice(1)];
}

function hasOptionBeforePassthrough(args, option) {
  for (const arg of args) {
    if (arg === "--") {
      return false;
    }
    if (arg === option) {
      return true;
    }
  }
  return false;
}
