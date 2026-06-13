#!/bin/sh
set -eu

repository="${ZYPHER_REPOSITORY:-zypher-org/zypher}"
requested_version="${ZYPHER_VERSION:-latest}"

say() {
  printf '%s\n' "$*"
}

fail() {
  printf 'zypher installer: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
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

resolve_version() {
  if [ "$requested_version" != "latest" ]; then
    printf '%s\n' "${requested_version#v}"
    return
  fi

  latest_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repository/releases/latest")"
  latest_tag="${latest_url##*/}"
  case "$latest_tag" in
    v*) printf '%s\n' "${latest_tag#v}" ;;
    *) fail "could not resolve latest release from $latest_url" ;;
  esac
}

resolve_targets() {
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os-$arch" in
    Linux-x86_64)
      zypher_target="x86_64-linux-musl"
      zig_target="x86_64-linux"
      ;;
    Linux-aarch64|Linux-arm64)
      zypher_target="aarch64-linux-musl"
      zig_target="aarch64-linux"
      ;;
    Darwin-x86_64)
      zypher_target="x86_64-macos"
      zig_target="x86_64-macos"
      ;;
    Darwin-arm64|Darwin-aarch64)
      zypher_target="aarch64-macos"
      zig_target="aarch64-macos"
      ;;
    *)
      fail "unsupported platform: $os $arch"
      ;;
  esac
}

download() {
  url="$1"
  output="$2"
  curl -fL --proto '=https' --tlsv1.2 "$url" -o "$output"
}

verify_sha256() {
  archive="$1"
  sums="$2"
  archive_name="$(basename "$archive")"

  if command -v sha256sum >/dev/null 2>&1; then
    expected="$(awk -v name="$archive_name" '$2 == name { print $1 }' "$sums")"
    [ -n "$expected" ] || fail "checksum for $archive_name not found"
    actual="$(sha256sum "$archive" | awk '{ print $1 }')"
    [ "$actual" = "$expected" ] || fail "checksum mismatch for $archive_name"
  elif command -v shasum >/dev/null 2>&1; then
    expected="$(awk -v name="$archive_name" '$2 == name { print $1 }' "$sums")"
    [ -n "$expected" ] || fail "checksum for $archive_name not found"
    actual="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
    [ "$actual" = "$expected" ] || fail "checksum mismatch for $archive_name"
  else
    say "warning: sha256sum/shasum not found; skipping Zypher release checksum verification"
  fi
}

install_zig() {
  zig_version="${ZYPHER_ZIG_VERSION:-$(awk -F\" '/\.minimum_zig_version =/ { print $2; exit }' "$source_dir/build.zig.zon")}"
  [ -n "$zig_version" ] || fail "could not read .minimum_zig_version from $source_dir/build.zig.zon"

  zig_dir="$zypher_home/zig/$zig_version/$zig_target"
  if [ -x "$zig_dir/zig" ]; then
    return
  fi

  say "Installing Zig $zig_version for $zig_target"
  tmp_zig="$tmp_dir/zig"
  mkdir -p "$tmp_zig" "$(dirname "$zig_dir")"
  zig_archive_name="zig-$zig_target-$zig_version.tar.xz"
  zig_archive="$tmp_zig/$zig_archive_name"

  index="$tmp_zig/index.json"
  download "https://ziglang.org/download/index.json" "$index"

  if command -v jq >/dev/null 2>&1; then
    zig_entry=$(jq -r --arg ver "$zig_version" '.[$ver] // (to_entries[] | select(.value.version == $ver) | .value) // empty' "$index")
    if [ -z "$zig_entry" ] || [ "$zig_entry" = "null" ]; then
      fail "could not find Zig $zig_version in release index"
    fi
    zig_tarball=$(echo "$zig_entry" | jq -r --arg tgt "$zig_target" '.[$tgt].tarball // empty')
  else
    line_num=$(grep -n -F "$zig_archive_name" "$index" | head -1 | cut -d: -f1)
    if [ -z "$line_num" ]; then
      fail "could not find Zig $zig_version for $zig_target in release index"
    fi
    zig_tarball=$(sed -n "${line_num}p" "$index" | sed 's/.*"tarball": "\([^"]*\)".*/\1/')
  fi

  if [ -z "$zig_tarball" ]; then
    fail "could not resolve download URL for Zig $zig_version $zig_target"
  fi

  download "$zig_tarball" "$zig_archive"
  tar -xJf "$zig_archive" -C "$tmp_zig"
  rm -rf "$zig_dir.partial-$$"
  mv "$tmp_zig/zig-$zig_target-$zig_version" "$zig_dir.partial-$$"
  rm -rf "$zig_dir"
  mv "$zig_dir.partial-$$" "$zig_dir"
}

install_zypher() {
  release_base="https://github.com/$repository/releases/download/v$version"
  archive_name="zypher-v$version-$zypher_target.tar.gz"
  archive_path="$tmp_dir/$archive_name"
  sums_path="$tmp_dir/SHA256SUMS"
  extract_dir="$tmp_dir/extract"

  say "Installing Zypher $version for $zypher_target"
  download "$release_base/$archive_name" "$archive_path"
  download "$release_base/SHA256SUMS" "$sums_path"
  verify_sha256 "$archive_path" "$sums_path"

  mkdir -p "$extract_dir"
  tar -xzf "$archive_path" -C "$extract_dir"
  package_dir="$extract_dir/zypher-v$version-$zypher_target"
  [ -d "$package_dir" ] || fail "release archive did not contain $package_dir"

  native_dir="$zypher_home/bin/$version/$zypher_target"
  source_dir="$zypher_home/source/$version"
  mkdir -p "$native_dir" "$(dirname "$source_dir")"
  cp "$package_dir/zypher" "$native_dir/zypher-bin"
  chmod 755 "$native_dir/zypher-bin"

  rm -rf "$source_dir.partial-$$"
  mkdir -p "$source_dir.partial-$$"
  cp -R "$package_dir/source/." "$source_dir.partial-$$/"
  rm -rf "$source_dir"
  mv "$source_dir.partial-$$" "$source_dir"
  [ -f "$source_dir/src/zypher.zig" ] || fail "installed source tree is missing src/zypher.zig"
}

install_wrapper() {
  bin_dir="$(resolve_bin_dir)"
  wrapper="$bin_dir/zypher"
  zig_version="${ZYPHER_ZIG_VERSION:-$(awk -F\" '/\.minimum_zig_version =/ { print $2; exit }' "$source_dir/build.zig.zon")}"
  [ -n "$zig_version" ] || fail "could not read .minimum_zig_version from $source_dir/build.zig.zon"

  zig_dir="$zypher_home/zig/$zig_version/$zig_target"
  native_dir="$zypher_home/bin/$version/$zypher_target"
  source_dir="$zypher_home/source/$version"

  mkdir -p "$bin_dir"
  cat > "$wrapper" <<EOF
#!/bin/sh
set -eu

zig_dir="$zig_dir"
source_dir="$source_dir"
native="$native_dir/zypher-bin"

export PATH="\$zig_dir:\$PATH"
export ZYPHER_ROOT="\$source_dir"

if [ "\$#" -gt 0 ]; then
  case "\$1" in
    run|doc|doc-user)
      cmd="\$1"
      shift
      exec "\$native" "\$cmd" --zypher-root "\$source_dir" "\$@"
      ;;
  esac
fi

exec "\$native" "\$@"
EOF
  chmod 755 "$wrapper"

  say "Installed zypher to $wrapper"
  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) say "Add this to your shell profile: export PATH=\"$bin_dir:\$PATH\"" ;;
  esac
}

need_cmd curl
need_cmd mktemp
need_cmd tar
need_cmd uname
need_cmd awk

resolve_targets
version="$(resolve_version)"
zypher_home="$(resolve_zypher_home)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/zypher-install.XXXXXX")"
trap 'rm -rf "$tmp_dir" "$zypher_home"/zig/*/*.partial-$$ "$zypher_home"/source/*.partial-$$' EXIT INT TERM

install_zypher
install_zig
install_wrapper

say "zypher $version is ready."
