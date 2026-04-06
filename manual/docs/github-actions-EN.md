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
- `.github/workflows/docker-publish.yml`
  Publishes Docker Hub images with the default platform set:
  - `linux/amd64`
  - `linux/arm64`

## Required Repository Variables

- `CANGJIE_SDK_LINUX_AMD64_URL`
  Cangjie SDK download URL used by Linux x86_64 runners. It also serves as the host SDK for the `linux-aarch64` cross-target build.
- `CANGJIE_SDK_MACOS_AMD64_URL`
  SDK URL for macOS Intel runners.
- `CANGJIE_SDK_MACOS_ARM64_URL`
  SDK URL for macOS Apple Silicon runners.
- `CANGJIE_STDX_GIT_REF`
  Optional. Defaults to `v1.1.0-beta.25`.
- `CANGJIE_STDX_REPO`
  Optional. Defaults to `https://gitcode.com/Cangjie/cangjie_stdx`.

## Docker Publishing Secrets

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`
- `GITCODE_USERNAME`
- `GITCODE_TOKEN`
- `ATOMGIT_USERNAME`
- `ATOMGIT_TOKEN`

GitCode and AtomGit credentials are only needed when dependency repositories require authentication. Public read-only dependencies can leave them unset.

## Reuse The Same Script Locally

Once `CANGJIE_HOME` and `CANGJIE_STDX_PATH` are available locally, the same release script can be reused directly:

```bash
./scripts/build_release_target.sh \
  --target x86_64-unknown-linux-gnu \
  --target-dir ./target-release/linux-x86_64 \
  --archive-platform linux-x86_64 \
  --version 0.5.17
```

That command runs `cjpm build --target ...` and then produces `dist/releases/soonlink-core-<version>-<platform>.tar.gz`.

## Scripts

- `scripts/install_cangjie_ci.sh`
  Downloads the SDK, builds stdx, and exports CI environment variables.
- `scripts/build_release_target.sh`
  Runs the target build and packaging flow end-to-end.
- `scripts/build_release_bundle.sh`
  Packages an already-built binary with public assets.

## Notes

- `linux-aarch64` is currently built as a target-triple build from an x86_64 Linux runner. If a future nightly regresses that cross-target path, move that matrix entry to a native ARM64 runner.
- Windows bundles are intentionally not part of this workflow yet because the repository does not currently have a stable Windows SDK URL and packaging chain. Add the fifth matrix entry once the Windows target becomes reproducible.
