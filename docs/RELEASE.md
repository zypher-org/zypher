# Release Process

Zypher releases are driven from `main`, annotated Git tags, or manual dispatch.
Pushes to `main` read `npm/package.json`, move `v<VERSION>` to the pushed
commit, and run the full release workflow. Tags matching `v*` and manual
dispatches use the selected tag directly. The full release workflow builds all
supported CLI targets, publishes a GitHub release, publishes the npm package,
renders a Homebrew formula with release checksums, and optionally pushes that
formula to the Homebrew tap.

## Required Secrets

- `NPM_TOKEN` publishes the `@zypher-org/zypher` package to npm. The installed
  binary command remains `zypher`.
- `HOMEBREW_TAP_REPO` names the tap repository to update, for example
  `zypher-org/homebrew-tap`.
- `HOMEBREW_TAP_TOKEN` pushes the rendered formula to the tap repository.

Missing npm credentials fail the release workflow. Homebrew tap credentials are
optional for now; when absent, the workflow still uploads `zypher.rb` to the
GitHub release and skips only the tap update.

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

## Beta Release

Create an annotated beta tag from the commit to release, or push `main` after
setting `npm/package.json` to the desired version:

```sh
git tag -a v0.1.0-beta -m "v0.1.0-beta beta release"
git push origin main
git push origin v0.1.0-beta
```

Prerelease versions containing a hyphen publish to npm with the `beta` dist-tag.
Stable versions publish with the `latest` dist-tag.
