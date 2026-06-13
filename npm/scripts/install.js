"use strict";

const childProcess = require("node:child_process");
const fs = require("node:fs");
const https = require("node:https");
const os = require("node:os");
const path = require("node:path");

const packageJson = require("../package.json");

const repository = "zypher-org/zypher";
const crypto = require("node:crypto");
const version = packageJson.version;
const zigVersion = packageJson.zypher.zigVersion;
const target = resolveTarget(process.platform, process.arch);
const archiveName = `zypher-v${version}-${target}.tar.gz`;
const downloadUrl = `https://github.com/${repository}/releases/download/v${version}/${archiveName}`;
const sumsUrl = `https://github.com/${repository}/releases/download/v${version}/SHA256SUMS`;
const vendorDir = path.join(__dirname, "..", "vendor", target);
const exeName = process.platform === "win32" ? "zypher.exe" : "zypher";
const exePath = path.join(vendorDir, exeName);
const zypherHome = resolveZypherHome();
const zigTarget = resolveZigTarget(process.platform, process.arch);
const zigArchiveExt = process.platform === "win32" ? "zip" : "tar.xz";
const zigArchiveName = `zig-${zigTarget}-${zigVersion}.${zigArchiveExt}`;
const zigIndexUrl = "https://ziglang.org/download/index.json";
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
    const sumsPath = path.join(tmpDir, "SHA256SUMS");
    await download(sumsUrl, sumsPath);
    await verifySha256(archivePath, sumsPath);
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

    const indexJson = await httpsGet(zigIndexUrl);
    const index = JSON.parse(indexJson);
    let entry = index[zigVersion];
    if (!entry) {
      for (const key of Object.keys(index)) {
        if (index[key].version === zigVersion) {
          entry = index[key];
          break;
        }
      }
    }
    if (!entry) {
      throw new Error(`could not find Zig ${zigVersion} in release index`);
    }
    const targetEntry = entry[zigTarget];
    if (!targetEntry) {
      throw new Error(`could not find Zig ${zigVersion} for ${zigTarget} in release index`);
    }
    const zigDownloadUrl = targetEntry.tarball;

    await download(zigDownloadUrl, archivePath);
    extractArchive(archivePath, extractDir, zigArchiveExt);

    const extractedDir = path.join(extractDir, `zig-${zigTarget}-${zigVersion}`);
    fs.rmSync(partialInstallDir, { recursive: true, force: true });
    moveDirectory(extractedDir, partialInstallDir);
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
    moveDirectory(extractedDir, partialInstallDir);
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

function httpsGet(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { "User-Agent": "zypher-npm-installer" } }, (response) => {
      if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
        response.resume();
        httpsGet(response.headers.location).then(resolve, reject);
        return;
      }
      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(`HTTP ${response.statusCode}: ${url}`));
        return;
      }
      let data = "";
      response.on("data", (chunk) => data += chunk);
      response.on("end", () => resolve(data));
    }).on("error", reject);
  });
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

function verifySha256(archivePath, sumsPath) {
  return new Promise((resolve, reject) => {
    const archiveName = path.basename(archivePath);
    const sums = fs.readFileSync(sumsPath, "utf8");
    let expected = null;
    for (const line of sums.split("\n")) {
      const parts = line.trim().split(/\s+/);
      if (parts.length === 2 && parts[1] === archiveName) {
        expected = parts[0].toLowerCase();
        break;
      }
    }
    if (!expected) {
      reject(new Error(`checksum for ${archiveName} not found`));
      return;
    }

    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(archivePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => {
      const actual = hash.digest("hex");
      if (actual !== expected) {
        reject(new Error(`checksum mismatch for ${archiveName}`));
      } else {
        console.log(`Checksum verified for ${archiveName}`);
        resolve();
      }
    });
    stream.on("error", reject);
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

function moveDirectory(source, destination) {
  try {
    fs.renameSync(source, destination);
  } catch (error) {
    if (!error || error.code !== "EXDEV") {
      throw error;
    }
    fs.cpSync(source, destination, { recursive: true });
    fs.rmSync(source, { recursive: true, force: true });
  }
}

function firstDirectory(parent) {
  const entries = fs.readdirSync(parent, { withFileTypes: true });
  const dir = entries.find((entry) => entry.isDirectory());
  if (!dir) {
    throw new Error(`archive did not contain a source directory`);
  }
  return path.join(parent, dir.name);
}
