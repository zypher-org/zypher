"use strict";

const childProcess = require("node:child_process");
const fs = require("node:fs");
const https = require("node:https");
const os = require("node:os");
const path = require("node:path");

const packageJson = require("../package.json");

const repository = "zypher-org/zypher";
const version = packageJson.version;
const target = resolveTarget(process.platform, process.arch);
const archiveName = `zypher-v${version}-${target}.tar.gz`;
const downloadUrl = `https://github.com/${repository}/releases/download/v${version}/${archiveName}`;
const vendorDir = path.join(__dirname, "..", "vendor", target);
const exeName = process.platform === "win32" ? "zypher.exe" : "zypher";
const exePath = path.join(vendorDir, exeName);

if (fs.existsSync(exePath)) {
  process.exit(0);
}

fs.mkdirSync(vendorDir, { recursive: true });

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "zypher-npm-"));
const archivePath = path.join(tmpDir, archiveName);
const extractDir = path.join(tmpDir, "extract");
fs.mkdirSync(extractDir);

download(downloadUrl, archivePath)
  .then(() => extractArchive(archivePath, extractDir))
  .then(() => {
    const packageDir = path.join(extractDir, `zypher-v${version}-${target}`);
    const extractedExe = path.join(packageDir, exeName);
    fs.copyFileSync(extractedExe, exePath);
    if (process.platform !== "win32") {
      fs.chmodSync(exePath, 0o755);
    }
  })
  .catch((error) => {
    console.error(`Failed to install zypher ${version} for ${target}.`);
    console.error(error.message);
    process.exit(1);
  })
  .finally(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

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

function extractArchive(archivePath, extractDir) {
  const result = childProcess.spawnSync("tar", ["-xzf", archivePath, "-C", extractDir], {
    stdio: "inherit",
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`tar exited with status ${result.status}`);
  }
}
