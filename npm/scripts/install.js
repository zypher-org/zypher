"use strict";

const childProcess = require("node:child_process");
const fs = require("node:fs");
const https = require("node:https");
const os = require("node:os");
const path = require("node:path");

const packageJson = require("../package.json");

const repository = "zypher-org/zypher";
const version = packageJson.version;
const zigVersion = packageJson.zypher.zigVersion;
const target = resolveTarget(process.platform, process.arch);
const archiveName = `zypher-v${version}-${target}.tar.gz`;
const downloadUrl = `https://github.com/${repository}/releases/download/v${version}/${archiveName}`;
const vendorDir = path.join(__dirname, "..", "vendor", target);
const exeName = process.platform === "win32" ? "zypher.exe" : "zypher";
const exePath = path.join(vendorDir, exeName);
const zypherHome = process.env.ZYPHER_HOME || path.join(os.homedir(), ".zypher");
const zigTarget = resolveZigTarget(process.platform, process.arch);
const zigArchiveExt = process.platform === "win32" ? "zip" : "tar.xz";
const zigArchiveName = `zig-${zigTarget}-${zigVersion}.${zigArchiveExt}`;
const zigDownloadUrl = `https://ziglang.org/builds/${zigArchiveName}`;
const zigInstallDir = path.join(zypherHome, "zig", zigVersion, zigTarget);
const zigExeName = process.platform === "win32" ? "zig.exe" : "zig";
const zigExePath = path.join(zigInstallDir, zigExeName);
const sourceArchiveName = `zypher-source-v${version}.tar.gz`;
const sourceDownloadUrl = `https://github.com/${repository}/archive/refs/tags/v${version}.tar.gz`;
const sourceInstallDir = path.join(zypherHome, "source", version);
const sourceMarkerPath = path.join(sourceInstallDir, "src", "zypher.zig");

install()
  .catch((error) => {
    console.error(`Failed to install zypher ${version} for ${target}.`);
    console.error(error.message);
    process.exit(1);
  });

async function install() {
  await installZypherBinary();
  await installZigToolchain();
  await installZypherSource();
}

async function installZypherBinary() {
  if (fs.existsSync(exePath)) {
    return;
  }

  fs.mkdirSync(vendorDir, { recursive: true });

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "zypher-npm-"));
  try {
    const archivePath = path.join(tmpDir, archiveName);
    const extractDir = path.join(tmpDir, "extract");
    fs.mkdirSync(extractDir);

    await download(downloadUrl, archivePath);
    extractArchive(archivePath, extractDir, "tar.gz");

    const packageDir = path.join(extractDir, `zypher-v${version}-${target}`);
    const extractedExe = path.join(packageDir, exeName);
    fs.copyFileSync(extractedExe, exePath);
    if (process.platform !== "win32") {
      fs.chmodSync(exePath, 0o755);
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

async function installZigToolchain() {
  if (!zigVersion) {
    throw new Error("npm/package.json is missing zypher.zigVersion");
  }
  if (fs.existsSync(zigExePath)) {
    return;
  }

  fs.mkdirSync(path.dirname(zigInstallDir), { recursive: true });

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "zypher-zig-"));
  const partialInstallDir = `${zigInstallDir}.partial-${process.pid}`;
  try {
    const archivePath = path.join(tmpDir, zigArchiveName);
    const extractDir = path.join(tmpDir, "extract");
    fs.mkdirSync(extractDir);

    await download(zigDownloadUrl, archivePath);
    extractArchive(archivePath, extractDir, zigArchiveExt);

    const extractedDir = path.join(extractDir, `zig-${zigTarget}-${zigVersion}`);
    fs.rmSync(partialInstallDir, { recursive: true, force: true });
    fs.renameSync(extractedDir, partialInstallDir);
    fs.rmSync(zigInstallDir, { recursive: true, force: true });
    fs.renameSync(partialInstallDir, zigInstallDir);

    if (process.platform !== "win32") {
      fs.chmodSync(zigExePath, 0o755);
    }
  } finally {
    fs.rmSync(partialInstallDir, { recursive: true, force: true });
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

async function installZypherSource() {
  if (fs.existsSync(sourceMarkerPath)) {
    return;
  }

  fs.mkdirSync(path.dirname(sourceInstallDir), { recursive: true });

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "zypher-source-"));
  const partialInstallDir = `${sourceInstallDir}.partial-${process.pid}`;
  try {
    const archivePath = path.join(tmpDir, sourceArchiveName);
    const extractDir = path.join(tmpDir, "extract");
    fs.mkdirSync(extractDir);

    await download(sourceDownloadUrl, archivePath);
    extractArchive(archivePath, extractDir, "tar.gz");

    const extractedDir = firstDirectory(extractDir);
    fs.rmSync(partialInstallDir, { recursive: true, force: true });
    fs.renameSync(extractedDir, partialInstallDir);
    fs.rmSync(sourceInstallDir, { recursive: true, force: true });
    fs.renameSync(partialInstallDir, sourceInstallDir);

    if (!fs.existsSync(sourceMarkerPath)) {
      throw new Error(`installed source tree is missing ${sourceMarkerPath}`);
    }
  } finally {
    fs.rmSync(partialInstallDir, { recursive: true, force: true });
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
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

  const target = targets[key];
  if (!target) {
    throw new Error(`Unsupported platform or architecture: ${platform} ${arch}`);
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
    throw new Error(`Unsupported platform or architecture for Zig: ${platform} ${arch}`);
  }

  return target;
}

function download(url, destination) {
  return new Promise((resolve, reject) => {
    const request = https.get(
      url,
      {
        headers: {
          "User-Agent": "zypher-npm-installer",
        },
      },
      (response) => {
        if (
          response.statusCode >= 300 &&
          response.statusCode < 400 &&
          response.headers.location
        ) {
          response.resume();
          download(response.headers.location, destination).then(resolve, reject);
          return;
        }

        if (response.statusCode !== 200) {
          response.resume();
          reject(new Error(`Download failed with HTTP ${response.statusCode}: ${url}`));
          return;
        }

        const file = fs.createWriteStream(destination);
        response.pipe(file);
        file.on("finish", () => {
          file.close(resolve);
        });
        file.on("error", reject);
      },
    );

    request.on("error", reject);
  });
}

function extractArchive(archivePath, extractDir, kind) {
  let result;
  if (kind === "zip") {
    result = childProcess.spawnSync(
      "powershell.exe",
      ["-NoProfile", "-Command", `Expand-Archive -LiteralPath '${escapePowerShell(archivePath)}' -DestinationPath '${escapePowerShell(extractDir)}' -Force`],
      { stdio: "inherit" },
    );
  } else if (kind === "tar.xz") {
    result = childProcess.spawnSync("tar", ["-xJf", archivePath, "-C", extractDir], {
      stdio: "inherit",
    });
  } else {
    result = childProcess.spawnSync("tar", ["-xzf", archivePath, "-C", extractDir], {
      stdio: "inherit",
    });
  }

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`archive extraction exited with status ${result.status}`);
  }
}

function escapePowerShell(value) {
  return value.replace(/'/g, "''");
}

function firstDirectory(parent) {
  const entries = fs.readdirSync(parent, { withFileTypes: true });
  const dir = entries.find((entry) => entry.isDirectory());
  if (!dir) {
    throw new Error(`archive did not contain a source directory`);
  }
  return path.join(parent, dir.name);
}
