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
const zypherHome = process.env.ZYPHER_HOME || path.join(os.homedir(), ".zypher");
const zigBinDir = path.join(zypherHome, "zig", zigVersion, zigTarget);

if (!fs.existsSync(exePath)) {
  console.error(`zypher binary is missing for ${target}. Try reinstalling the package.`);
  process.exit(1);
}

const pathKey = resolvePathKey(process.env);
const childEnv = {
  ...process.env,
  [pathKey]: [zigBinDir, process.env[pathKey]].filter(Boolean).join(path.delimiter),
};

const result = spawnSync(exePath, process.argv.slice(2), {
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
