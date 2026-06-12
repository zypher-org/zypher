# Release Process

Zypher releases are driven by `prod-nightly` branch pushes and annotated Git
tags matching `v*`.

- Pushes to `prod-nightly` publish the nightly package family: `zypher-cli`.
  The workflow derives a unique semver prerelease from `build.zig.zon`, for
  example `0.1.0-beta.nightly.123`, and publishes it under the matching
  generated GitHub release tag.
- Tags whose commits are on `prod-nightly` and not on `prod-stable` also
  publish the nightly package family: `zypher-cli`.
- Tags whose commits are on `prod-stable` publish the stable binary package
  family: `zypher-cli-bin`.

Both release workflows build all supported CLI targets, publish a GitHub
release, publish npm when credentials are available, render a Homebrew formula
with release checksums, and publish Chocolatey packages when those channel
credentials are available. AUR publishing is intentionally skipped for now and
tracked as release-distribution TODO work.

## Required Secrets

- `NPM_TOKEN` publishes `zypher-cli` from `prod-nightly` and `zypher-cli-bin`
  from `prod-stable`. The installed binary command remains `zypher`.
- `HOMEBREW_TAP_REPO` names the tap repository to update, for example
  `zypher-org/homebrew-tap`.
- `HOMEBREW_TAP_TOKEN` pushes the rendered formula to the tap repository.
- `CHOCOLATEY_API_KEY` pushes the rendered Chocolatey package.

Package-manager credentials are optional in CI. When a secret is absent, the
matching publish step is skipped; GitHub release artifacts are still produced.

## CLI Runtime Dependencies

The published npm package and release binaries embed all template files at
compile time. Template discovery therefore does not require a Zypher source
tree.

All package-manager installs use the Zig version pinned in
`build.zig.zon` (`.minimum_zig_version`) rather than whatever Zig version the
host package manager currently provides.

The npm package installs:

- the pinned Zig toolchain declared in `npm/package.json`
- the tagged Zypher source tree, including `vendor/sqlite-amalgamation-*`

These are stored under:

```text
~/.zypher/zig/<zig-version>/<zig-target>/
~/.zypher/source/<zypher-version>/
```

The npm `zypher` wrapper prepends that directory to `PATH` before launching the
native CLI and passes the source path as `--zypher-root` for commands that need
it. This lets commands that invoke `zig build` resolve both `zig` and Zypher's
vendored SQLite-backed source tree after npm install without additional shell
setup.

The standalone `install.sh` script provides the same runtime layout for
curl-based installs:

```sh
curl -fsSL https://raw.githubusercontent.com/zypher-org/zypher/main/install.sh | sh
```

It resolves the latest GitHub release unless `ZYPHER_VERSION` is set, detects
the current OS/architecture, downloads the matching Zypher release archive,
parses the release source tree's `build.zig.zon`, downloads that pinned Zig
binary from `https://ziglang.org/builds/`, and writes the user-facing wrapper to
`~/.local/bin/zypher` by default.

Native package-manager wrappers use the same layout under the invoking user's
home directory:

```text
~/.zypher/zig/<zig-version>/<zig-target>/
~/.zypher/source/<zypher-version>/
```

The wrappers prepend the pinned Zig directory to `PATH`, export
`ZYPHER_ROOT=~/.zypher/source/<zypher-version>`, and pass `--zypher-root` for
build-backed commands. When invoked through sudo/elevated package-manager
flows, the runtime cache still targets the invoking user's home directory when
that home can be resolved by the platform.

Native packages also keep a copy of the release source tree beside the packaged
binary so wrappers can populate `~/.zypher/source/<zypher-version>` without
requiring a separate source checkout.

## AUR TODO

AUR templates are kept in `packaging/aur/`, but the release workflows
intentionally disable AUR publishing until the package ownership, review, and
runtime bootstrap policy are finalized. Do not treat `AUR_SSH_KEY` as an active
release credential yet.

The following CLI commands work without a Zypher source tree:

- `help` — show help
- `new` — scaffold projects from embedded templates (8 variants)
- `demo` — shortcut for `new --template mvc`
- `templates` — list available embedded templates
- `runserver` — start a health-check HTTP server
- `createsuperuser` — create admin users in a SQLite database
- `migrate` — run SQL migrations
- `shell` — interactive REPL

Commands that build code require Zig to be available through the pinned
`~/.zypher` toolchain installed by the npm package, native wrappers, or
standalone installer:

- `run` — runs a scaffolded app via `zig build run`
- `doc` — builds and serves Zypher library docs via `zig build doc`
- `doc-user` — builds and serves user project docs

`doc` additionally requires a Zypher source tree. `run` and `doc-user` operate
on generated/user projects and use their local `build.zig` files.

## Supported Release Assets

Each release publishes these archives:

- `zypher-v<VERSION>-x86_64-linux-musl.tar.gz`
- `zypher-v<VERSION>-aarch64-linux-musl.tar.gz`
- `zypher-v<VERSION>-x86_64-macos.tar.gz`
- `zypher-v<VERSION>-aarch64-macos.tar.gz`
- `zypher-v<VERSION>-x86_64-windows-gnu.tar.gz`
- `zypher-v<VERSION>-aarch64-windows-gnu.tar.gz`
- `SHA256SUMS`
- `install.sh`
- `zypher-cli.rb` for nightly releases, or `zypher-cli-bin.rb` for stable
  releases

## npm Installation

Install the nightly CLI globally:

```sh
npm install -g zypher-cli@latest
zypher help
```

If `npm install -g` fails with `EACCES` because npm is writing to a system
prefix such as `/usr/lib/node_modules`, move global npm packages to a user-owned
prefix:

```sh
mkdir -p ~/.local
npm config set prefix ~/.local
export PATH="$HOME/.local/bin:$PATH"
npm install -g zypher-cli@latest
```

The `PATH` export should be added to the user's shell profile. Package scripts
cannot change npm's global install prefix before npm creates the package
directory. Avoid `sudo npm install -g` when possible; when sudo is used, the
Zypher npm wrapper resolves its cache root to the invoking user's `~/.zypher`
directory instead of `/root/.zypher`.

The postinstall script downloads the matching native `zypher` binary from the
GitHub release, installs Zig from `ziglang.org`, and installs the matching
tagged Zypher source tree into `~/.zypher`.

Install an exact nightly version:

```sh
npm install -g zypher-cli@0.1.0-beta
zypher help
```

Install a stable binary package:

```sh
npm install -g zypher-cli-bin@latest
zypher help
```

Run without a global install:

```sh
npx zypher-cli@latest help
```

For project-local use:

```sh
npm install --save-dev zypher-cli@latest
npx zypher help
```

## Native Package Installation

The package name depends on the release branch. The installed command remains
`zypher`. AUR commands are shown as TODO until AUR publishing is enabled.

Nightly packages from `prod-nightly`:

```sh
brew install zypher-cli
# TODO: paru -S zypher-cli
# TODO: yay -S zypher-cli
choco install zypher-cli
```

Stable binary packages from `prod-stable`:

```sh
brew install zypher-cli-bin
# TODO: paru -S zypher-cli-bin
# TODO: yay -S zypher-cli-bin
choco install zypher-cli-bin
```

## Nightly Release

Push the commit to `prod-nightly`:

```sh
git push origin HEAD:prod-nightly
```

The workflow publishes a generated nightly version based on the
`build.zig.zon` version and the GitHub Actions run number.

You can also create an annotated beta tag from the commit to release, then push
it after the commit is present on `prod-nightly`:

```sh
git tag -a v0.1.0-beta -m "v0.1.0-beta beta release"
git push origin v0.1.0-beta
```

## Stable Release

Create a stable tag after promoting the commit to `prod-stable`:

```sh
git tag -a v0.1.0 -m "v0.1.0 stable release"
git push origin v0.1.0
```

Nightly npm publishes with the `latest` dist-tag. Stable npm also publishes
with the `latest` dist-tag for the `zypher-cli-bin` package. GitHub releases,
including tag-triggered releases from both `prod-nightly` and `prod-stable`, are
explicitly marked latest by the release workflows so the repository sidebar
points at the most recent published Zypher release.
