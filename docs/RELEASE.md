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

## Standalone Binary Capabilities

The published npm package and release binaries embed all template files at
compile time. The following CLI commands work **without** a Zypher source tree
or Zig compiler:

- `help` — show help
- `new` — scaffold projects from embedded templates (8 variants)
- `demo` — shortcut for `new --template mvc`
- `templates` — list available embedded templates
- `runserver` — start a health-check HTTP server
- `createsuperuser` — create admin users in a SQLite database
- `migrate` — run SQL migrations
- `shell` — interactive REPL

Commands that require a Zig development environment and Zypher source tree:

- `run` — runs a scaffolded app via `zig build run`
- `doc` — builds and serves Zypher library docs via `zig build doc`
- `doc-user` — builds and serves user project docs

These commands fail with a clear error message when `zig` or the source tree
is not available.

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
