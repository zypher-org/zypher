#Requires -Version 5.1
param(
  [string]$ZyphEHome = ${env:ZYPHER_HOME:-""},
  [string]$ZyphEBinDir = ${env:ZYPHER_BIN_DIR:-""}
)

$ErrorActionPreference = "Stop"

function Say($msg) { Write-Host $msg }

function Resolve-ZyphEHome {
  if ($ZyphEHome) { return $ZyphEHome }
  return "$HOME\.zypher"
}

function Resolve-BinDir {
  if ($ZyphEBinDir) { return $ZyphEBinDir }
  return "$HOME\.local\bin"
}

$zypherHome = Resolve-ZyphEHome
$binDir = Resolve-BinDir
$wrapper = "$binDir\zypher.cmd"
$removedAny = $false

if (Test-Path $wrapper) {
  Remove-Item -Force $wrapper
  Say "Removed wrapper: $wrapper"
  $removedAny = $true
}

$wrapperPs1 = "$binDir\zypher.ps1"
if (Test-Path $wrapperPs1) {
  Remove-Item -Force $wrapperPs1
  Say "Removed wrapper: $wrapperPs1"
  $removedAny = $true
}

if (Test-Path $zypherHome) {
  Remove-Item -Recurse -Force $zypherHome
  Say "Removed Zypher data: $zypherHome"
  $removedAny = $true
}

if (-not $removedAny) {
  Say "Zypher does not appear to be installed (no wrapper at $wrapper, no data at $zypherHome)."
  exit 0
}

Say "Zypher has been uninstalled."
