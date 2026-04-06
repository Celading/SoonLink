# GitHub Actions / Release

SoonLink Core now includes a GitHub-oriented automation skeleton so source CI, release bundles, and Docker publishing can evolve as separate but reusable lanes.

## Workflows

- `.github/workflows/core-ci.yml`
  Public-boundary checks, Compose validation, and a lightweight build smoke test.
- `.github/workflows/release-artifacts.yml`
  Builds GitHub Release bundles for:
  - `linux-x86_64`
  - `linux-aarch64`
  - `darwin-x86_64`
  - `darwin-aarch64`
  - `windows-x86_64`
- `.github/workflows/docker-publish.yml`
  Publishes Docker Hub images with the default platform set:
  - `linux/amd64`
  - `linux/arm64`
- `.github/workflows/homebrew-tap.yml`
  After a GitHub Release is published, renders the Homebrew formula from the Darwin x64 / arm64 bundles and pushes it to the tap repository.

## Required Repository Variables

- `CANGJIE_SDK_LINUX_AMD64_URL`
  Cangjie SDK download URL used by Linux x86_64 runners.
- `CANGJIE_SDK_LINUX_ARM64_URL`
  Cangjie SDK download URL used by Linux ARM64 runners. The `linux-aarch64` release bundle now runs on a native `ubuntu-24.04-arm` runner.
- `CANGJIE_SDK_MACOS_AMD64_URL`
  SDK URL for macOS Intel runners.
- `CANGJIE_SDK_MACOS_ARM64_URL`
  SDK URL for macOS Apple Silicon runners.
- `CANGJIE_SDK_WINDOWS_AMD64_URL`
  SDK URL for Windows x64 runners.
- `CANGJIE_STDX_GIT_REF`
  Optional. Defaults to `v1.1.0-beta.25`.
- `CANGJIE_STDX_REPO`
  Optional. Defaults to `https://gitcode.com/Cangjie/cangjie_stdx`.
- `HOMEBREW_TAP_REPO`
  Target tap repository, for example `Celading/homebrew-tap`.
- `HOMEBREW_TAP_BRANCH`
  Optional. Defaults to `main`.

## Docker Publishing Secrets

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`
- `GITCODE_USERNAME`
- `GITCODE_TOKEN`
- `ATOMGIT_USERNAME`
- `ATOMGIT_TOKEN`
- `HOMEBREW_TAP_TOKEN`

GitCode and AtomGit credentials are only needed when dependency repositories require authentication. Public read-only dependencies can leave them unset. `HOMEBREW_TAP_TOKEN` is used to push the generated formula into the tap repository.

## Reuse The Same Script Locally

Once `CANGJIE_HOME` and `CANGJIE_STDX_PATH` are available locally, the same release script can be reused directly:

```bash
./scripts/build_release_target.sh \
  --target x86_64-unknown-linux-gnu \
  --target-dir ./target-release/linux-x86_64 \
  --archive-platform linux-x86_64 \
  --version 0.5.27
```

That command runs `cjpm build --target ...` and then produces `dist/releases/soonlink-core-<version>-<platform>.tar.gz`.

## Scripts

- `scripts/install_cangjie_ci.sh`
  Downloads the SDK, builds stdx, and exports CI environment variables.
- `scripts/build_release_target.sh`
  Runs the target build and packaging flow end-to-end.
- `scripts/build_release_bundle.sh`
  Packages an already-built binary with public assets.
- `scripts/prepare_release_workspace.sh`
  Prepares a clean SoonLink + Ignite + lisi + jinguiSSL workspace in CI and rewrites dependencies into local `path` references.

## Notes

- Pushing tags such as `0.8.27` or `0.0.5.17` automatically triggers `release-artifacts` and `docker-publish`; once the GitHub Release is published, `homebrew-tap` follows.
- The pushed tag must either match the `cjpm.toml` version exactly or append one extra dotted revision, for example release tag `0.5.27.1` on package version `0.5.27`.
- `linux-aarch64` now uses a native `ubuntu-24.04-arm` runner with an ARM64 SDK so release bundles do not depend on x86_64 Linux SDK layouts that omit `linux_aarch64_cjnative` modules.
- Windows is currently limited to `windows-x86_64`. Do not promise Windows ARM64 publicly until the SDK and stdx layout become reproducible.
