#Requires -Version 5.1
param(
  [string]$ZyphERepository = ${env:ZYPHER_REPOSITORY:-"zypher-org/zypher"},
  [string]$ZyphEVersion = ${env:ZYPHER_VERSION:-"latest"},
  [string]$ZigVersion = ${env:ZYPHER_ZIG_VERSION:-""},
  [string]$ZyphEHome = ${env:ZYPHER_HOME:-""},
  [string]$ZyphEBinDir = ${env:ZYPHER_BIN_DIR:-""}
)

$ErrorActionPreference = "Stop"

function Say($msg) { Write-Host $msg }
function Fail($msg) { Write-Host "zypher installer: $msg" -ForegroundColor Red; exit 1 }

function Resolve-ZyphEHome {
  if ($ZyphEHome) { return $ZyphEHome }
  return "$HOME\.zypher"
}

function Resolve-BinDir {
  if ($ZyphEBinDir) { return $ZyphEBinDir }
  return "$HOME\.local\bin"
}

function Resolve-Version {
  param([string]$Requested)
  if ($Requested -ne "latest") { return $Requested.TrimStart('v') }
  $url = "https://github.com/$ZyphERepository/releases/latest"
  try {
    $request = [System.Net.WebRequest]::Create($url)
    $request.AllowAutoRedirect = $false
    $response = $request.GetResponse()
    $location = $response.GetResponseHeader("Location")
    $response.Close()
    $tag = $location -split '/' | Select-Object -Last 1
    if ($tag -match '^v(.+)$') { return $matches[1] }
    Fail "could not resolve latest release from $url"
  } catch { Fail "could not resolve latest release: $_" }
}

function Resolve-Target {
  $os = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
  $arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "aarch64" }
  if ($arch -eq "x86_64") { return "x86_64-windows-gnu" }
  return "aarch64-windows-gnu"
}

function Get-ArchSuffix {
  $arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "aarch64" }
  if ($arch -eq "x86_64") { return "x64" }
  return "arm64"
}

function Get-ZigTarget {
  $arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "aarch64" }
  return "$arch-windows"
}

function Download-File {
  param([string]$Url, [string]$Output)
  Write-Host "Downloading $Url"
  $ProgressPreference = "SilentlyContinue"
  try {
    $client = New-Object System.Net.WebClient
    $client.DownloadFile($Url, $Output)
  } catch { Fail "download failed: $_" }
}

function Verify-Sha256 {
  param([string]$ArchivePath, [string]$SumsPath)
  $archiveName = Split-Path -Leaf $ArchivePath
  $expected = (Get-Content $SumsPath | Where-Object { $_ -match "$archiveName" }) -split '\s+' | Select-Object -First 1
  if (-not $expected) { Fail "checksum for $archiveName not found in $SumsPath" }
  $actual = (Get-FileHash $ArchivePath -Algorithm SHA256).Hash.ToLower()
  if ($actual -ne $expected.ToLower()) { Fail "checksum mismatch for $archiveName" }
  Say "Checksum verified for $archiveName"
}

function Install-Zypher {
  $releaseBase = "https://github.com/$ZyphERepository/releases/download/v$version"
  $archiveName = "zypher-v$version-$target.tar.gz"
  $archivePath = "$tmpDir\$archiveName"
  $sumsPath = "$tmpDir\SHA256SUMS"
  $extractDir = "$tmpDir\extract"

  Say "Installing Zypher $version for $target"
  Download-File "$releaseBase/$archiveName" $archivePath
  Download-File "$releaseBase/SHA256SUMS" $sumsPath
  Verify-Sha256 $archivePath $sumsPath

  New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
  tar -xzf $archivePath -C $extractDir
  if ($LASTEXITCODE -ne 0) { Fail "failed to extract $archiveName" }

  $packageDir = "$extractDir\zypher-v$version-$target"
  if (-not (Test-Path $packageDir)) { Fail "release archive did not contain $packageDir" }

  $nativeDir = "$zypherHome\bin\$version\$target"
  $sourceDir = "$zypherHome\source\$version"
  New-Item -ItemType Directory -Force -Path $nativeDir | Out-Null
  New-Item -ItemType Directory -Force -Path (Split-Path $sourceDir) | Out-Null

  Copy-Item "$packageDir\zypher.exe" "$nativeDir\zypher-bin.exe" -Force

  if (Test-Path $sourceDir) { Remove-Item -Recurse -Force $sourceDir }
  $partialSource = "$sourceDir.partial-$pid"
  if (Test-Path $partialSource) { Remove-Item -Recurse -Force $partialSource }
  New-Item -ItemType Directory -Force -Path $partialSource | Out-Null
  Copy-Item "$packageDir\source\*" $partialSource -Recurse -Force
  Rename-Item $partialSource $sourceDir
  if (-not (Test-Path "$sourceDir\src\zypher.zig")) { Fail "installed source tree is missing src\zypher.zig" }
}

function Install-Zig {
  $resolvedZigVersion = if ($ZigVersion) { $ZigVersion } else {
    $zonPath = "$sourceDir\build.zig.zon"
    if (-not (Test-Path $zonPath)) { Fail "could not read .minimum_zig_version from $zonPath" }
    $zonContent = Get-Content $zonPath -Raw
    if ($zonContent -match '\.minimum_zig_version\s*=\s*"([^"]+)"') { $matches[1] } else { Fail "could not find .minimum_zig_version in build.zig.zon" }
  }
  if (-not $resolvedZigVersion) { Fail "could not determine Zig version" }

  $zigDir = "$zypherHome\zig\$resolvedZigVersion\$zigTarget"
  $zigExe = "$zigDir\zig.exe"
  if (Test-Path $zigExe) { return }

  Say "Installing Zig $resolvedZigVersion for $zigTarget"
  $tmpZig = "$tmpDir\zig"
  New-Item -ItemType Directory -Force -Path $tmpZig | Out-Null
  New-Item -ItemType Directory -Force -Path (Split-Path $zigDir) | Out-Null

  $zigArchiveName = "zig-$zigTarget-$resolvedZigVersion.zip"
  $zigArchivePath = "$tmpZig\$zigArchiveName"
  $zigUrl = "https://ziglang.org/builds/$zigArchiveName"
  Download-File $zigUrl $zigArchivePath

  $extractDir = "$tmpZig\extract"
  New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
  Expand-Archive -LiteralPath $zigArchivePath -DestinationPath $extractDir -Force

  $partialDir = "$zigDir.partial-$pid"
  if (Test-Path $partialDir) { Remove-Item -Recurse -Force $partialDir }
  $extractedDir = "$extractDir\zig-$zigTarget-$resolvedZigVersion"
  Move-Item $extractedDir $partialDir
  if (Test-Path $zigDir) { Remove-Item -Recurse -Force $zigDir }
  Rename-Item $partialDir $zigDir
}

function Install-Wrapper {
  $binDir = Resolve-BinDir
  $nativeDir = "$zypherHome\bin\$version\$target"
  $sourceDir = "$zypherHome\source\$version"

  New-Item -ItemType Directory -Force -Path $binDir | Out-Null

  $wrapper = "$binDir\zypher.cmd"
  @"
@echo off
set "ZYPHER_ROOT=$sourceDir"
set "PATH=$zypherHome\zig\$zigVersionResolved\$zigTarget;%PATH%"
"%~dp0\..\$nativeDir\zypher-bin.exe" %*
"@ | Out-File -FilePath $wrapper -Encoding ASCII
  Say "Installed zypher wrapper to $wrapper"

  $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
  if ($currentPath -notlike "*$binDir*") {
    Say "Add this to your PATH (already attempted user-scope):"
    Say "  [Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'User') + ';$binDir', 'User')"
  }
}

function Main {
  $script:target = Resolve-Target
  $script:zigTarget = Get-ZigTarget
  $script:version = Resolve-Version $ZyphEVersion
  $script:zypherHome = Resolve-ZyphEHome
  $script:zigVersionResolved = if ($ZigVersion) { $ZigVersion } else { "" }

  $script:tmpDir = Join-Path $env:TEMP "zypher-install.$pid"
  if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

  try {
    Install-Zypher
    Install-Zig
    Install-Wrapper
    Say "zypher $version is ready."
  } finally {
    if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue }
  }
}

Main
