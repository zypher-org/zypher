# Release Process

Zypher releases are driven from `main`, annotated Git tags, or manual dispatch.
Pushes to `main` read `npm/package.json`, move `v<VERSION>` to the pushed
commit, and run the full release workflow. Tags matching `v*` and manual
dispatches use the selected tag directly. The full release workflow builds all
supported CLI targets, publishes a normal/latest GitHub release, publishes the
npm package, renders a Homebrew formula with release checksums, and optionally
pushes that formula to the Homebrew tap.

## Required Secrets

- `NPM_TOKEN` publishes the `@zypher-org/zypher` package to npm. The installed
  binary command remains `zypher`.
- `HOMEBREW_TAP_REPO` names the tap repository to update, for example
  `zypher-org/homebrew-tap`.
- `HOMEBREW_TAP_TOKEN` pushes the rendered formula to the tap repository.

Missing npm credentials fail the release workflow. Homebrew tap credentials are
optional for now; when absent, the workflow still uploads `zypher.rb` to the
GitHub release and skips only the tap update.

## CLI Runtime Dependencies

The published npm package and release binaries embed all template files at
compile time. Template discovery therefore does not require a Zypher source
tree.

The npm package also installs the pinned Zig toolchain declared in
`npm/package.json` under:

```text
~/.zypher/zig/<zig-version>/<zig-target>/
```

The npm `zypher` wrapper prepends that directory to `PATH` before launching the
native CLI, so commands that invoke `zig build` can work after npm install
without additional shell setup.

Native package managers install Zig through their dependency systems:

- Homebrew formula: `depends_on "zig"`
- AUR package: `depends=('glibc' 'zig')`
- Chocolatey package: `zig` package dependency

The following CLI commands work without a Zypher source tree:

- `help` — show help
- `new` — scaffold projects from embedded templates (8 variants)
- `demo` — shortcut for `new --template mvc`
- `templates` — list available embedded templates
- `runserver` — start a health-check HTTP server
- `createsuperuser` — create admin users in a SQLite database
- `migrate` — run SQL migrations
- `shell` — interactive REPL

Commands that build code require Zig to be available through the npm-managed
`~/.zypher` toolchain or the platform package manager:

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
- `zypher.rb`

## npm Installation

Install the published CLI globally:

```sh
npm install -g @zypher-org/zypher@beta
zypher help
```

The postinstall script downloads the matching native `zypher` binary from the
GitHub release and installs Zig from `ziglang.org` into `~/.zypher`.

Install an exact beta version:

```sh
npm install -g @zypher-org/zypher@0.1.0-beta
zypher help
```

Run without a global install:

```sh
npx @zypher-org/zypher@beta help
```

For project-local use:

```sh
npm install --save-dev @zypher-org/zypher@beta
npx zypher help
```

## Beta Release

Create an annotated beta tag from the commit to release, or push `main` after
setting `npm/package.json` to the desired version:

```sh
git tag -a v0.1.0-beta -m "v0.1.0-beta beta release"
git push origin main
git push origin v0.1.0-beta
```

Prerelease versions containing a hyphen publish to npm with the `beta` dist-tag.
Stable versions publish with the `latest` dist-tag. GitHub releases are still
published as normal/latest releases so they appear in repository release
surfaces.
