#!/bin/sh
set -eu

say() {
  printf '%s\n' "$*"
}

warn() {
  printf 'zypher uninstaller: %s\n' "$*" >&2
}

resolve_base_home() {
  if [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    if command -v getent >/dev/null 2>&1; then
      sudo_home="$(getent passwd "$SUDO_USER" | awk -F: '{ print $6 }')"
      if [ -n "$sudo_home" ]; then
        printf '%s\n' "$sudo_home"
        return
      fi
    fi
  fi
  printf '%s\n' "$HOME"
}

resolve_zypher_home() {
  if [ -n "${ZYPHER_HOME:-}" ]; then
    printf '%s\n' "$ZYPHER_HOME"
    return
  fi
  base_home="$(resolve_base_home)"
  printf '%s/.zypher\n' "$base_home"
}

resolve_bin_dir() {
  if [ -n "${ZYPHER_BIN_DIR:-}" ]; then
    printf '%s\n' "$ZYPHER_BIN_DIR"
    return
  fi
  base_home="$(resolve_base_home)"
  printf '%s/.local/bin\n' "$base_home"
}

zypher_home="$(resolve_zypher_home)"
bin_dir="$(resolve_bin_dir)"
wrapper="$bin_dir/zypher"
removed_any=false

if [ -f "$wrapper" ]; then
  rm -f "$wrapper"
  say "Removed wrapper: $wrapper"
  removed_any=true
fi

if [ -d "$zypher_home" ]; then
  rm -rf "$zypher_home"
  say "Removed Zypher data: $zypher_home"
  removed_any=true
fi

if [ "$removed_any" = false ]; then
  say "Zypher does not appear to be installed (no wrapper at $wrapper, no data at $zypher_home)."
  exit 0
fi

say "Zypher has been uninstalled."
