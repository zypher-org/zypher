# Release Process

Zypher releases are driven by annotated Git tags. Tags matching `v*` trigger the
release workflow, which builds all supported CLI targets, publishes a GitHub
release, publishes the npm package, renders a Homebrew formula with release
checksums, and pushes that formula to the Homebrew tap.

## Required Secrets

- `NPM_TOKEN` publishes the `@zypher-org/zypher` package to npm. The installed
  binary command remains `zypher`.
- `HOMEBREW_TAP_REPO` names the tap repository to update, for example
  `zypher-org/homebrew-tap`.
- `HOMEBREW_TAP_TOKEN` pushes the rendered formula to the tap repository.

Missing npm or Homebrew tap credentials fail the release workflow. A green
release run means GitHub assets, npm, and Homebrew tap publishing all completed.

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

Create an annotated beta tag from the commit to release:

```sh
git tag -a v0.1.0-beta -m "v0.1.0-beta beta release"
git push origin prod-nightly
git push origin v0.1.0-beta
```

Prerelease versions containing a hyphen publish to npm with the `beta` dist-tag.
Stable versions publish with the `latest` dist-tag.
