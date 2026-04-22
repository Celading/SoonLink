# GitHub / GitCode CI & Release

SoonLink now keeps two automation lanes side by side:

- GitHub handles the full multi-platform release, Docker, and Homebrew publishing path.
- GitCode handles the repository Linux CI path and tag-driven Linux bundle assembly under `.gitcode/workflows/`.

That split keeps the repository validation path lightweight while leaving the full cross-platform release surface on GitHub.

## GitHub Workflows

- `.github/workflows/core-ci.yml`
  Repository-boundary checks, Compose validation, and a lightweight build smoke test.
  - When `CANGJIE_SDK_LINUX_AMD64_URL` is configured, the workflow now installs the Linux SDK and `stdx`, then runs real `cjpm build`, `cjpm test`, and container-bundle preparation.
  - When `CANGJIE_STDX_RELEASE_VERSION` is configured, CI prefers that official prebuilt `stdx` release package. When it is unset, Linux still falls back to source builds, while macOS / Windows / OpenHarmony jobs first try the release version derived from `CANGJIE_STDX_GIT_REF` and only then fall back to `1.0.0.1`.
  - It also clones `Ignite / lisi / jinguiSSL` and builds inside a temporary path-rewritten workspace instead of depending on the current repository's live git dependency shape.
  - When the repository variable is still missing, the workflow emits a warning and keeps the boundary and Compose checks only.
  - It now also includes an optional OpenHarmony `aarch64` cross-build smoke lane. When the Linux SDK is available and an OpenHarmony DEVECO bundle can be configured or auto-resolved, CI runs one `aarch64-linux-ohos` build as well.
- `.github/workflows/release-artifacts.yml`
  Builds GitHub Release bundles for:
  - `linux-x86_64`
  - `linux-aarch64`
  - `darwin-x86_64`
  - `darwin-aarch64`
  - `windows-x86_64`
  - When the OpenHarmony toolchain can be resolved, it also adds:
    - `ohos-aarch64`
  - When `CANGJIE_STDX_RELEASE_VERSION` is configured, release jobs reuse that official per-platform `stdx` bundle. When it is unset, macOS / Windows / OpenHarmony jobs first try the release version derived from `CANGJIE_STDX_GIT_REF` and only then fall back to `1.0.0.1`.
  - Each platform now emits both `.tar.gz` and `.zip` bundles so users can unpack a full runtime bundle more directly.
  - Each platform job now uploads staged artifacts first, and the Ubuntu `publish` job publishes the final GitHub Release assets in one place.
- `.github/workflows/docker-publish.yml`
  Publishes Docker Hub images with the default platform set:
  - `linux/amd64`
  - `linux/arm64`
- `.github/workflows/homebrew-tap.yml`
  After a GitHub Release is published, renders the Homebrew formula from the Darwin x64 / arm64 bundles and pushes it to the tap repository.

## GitCode Workflows

- `.gitcode/workflows/core-ci.yml`
  Runs the repository verification path on GitCode's default `euleros-2.10.1` runner.
  - After `checkout-action@0.0.1`, all commands execute inside `repo_workspace`.
  - The workflow runs the repository-boundary audit first, installs Linux prerequisites, installs the Cangjie SDK and `stdx`, clones `Ignite / lisi / jinguiSSL`, projects a clean temporary workspace, and then runs `cjpm build` plus `cjpm test`.
  - Compose validation only runs when `docker compose` is available on the runner. Missing Docker support is treated as a warning instead of a false CI regression.
- `.gitcode/workflows/release-linux.yml`
  Builds a GitCode-side Linux release bundle for tags and manual runs.
  - Triggered by `x.y.z` or `x.y.z.n` tags, or manually from the GitCode UI.
  - Currently emits `linux-x86_64` `.tar.gz` and `.zip` bundles plus `SHA256SUMS` under `dist/gitcode-release/`.
  - This workflow is meant to give the GitCode remote a reproducible tag packaging lane, not to replace the full GitHub multi-platform release publication.

## Variables and Credentials

- `CANGJIE_SDK_LINUX_AMD64_URL`
  Cangjie SDK download URL used by Linux x86_64 runners.
  - GitHub `core-ci` skips the real build when it is unset.
  - GitCode workflows fall back to the current default `1.1.0-beta.25` Linux x64 SDK URL when it is unset.
- `CANGJIE_SDK_LINUX_ARM64_URL`
  Cangjie SDK download URL used by Linux ARM64 runners. The `linux-aarch64` release bundle now runs on a native `ubuntu-24.04-arm` runner.
- `CANGJIE_SDK_MACOS_AMD64_URL`
  SDK URL for macOS Intel runners. When unset, the workflow falls back to the official `1.1.0-beta.25` SDK.
- `CANGJIE_SDK_MACOS_ARM64_URL`
  SDK URL for macOS Apple Silicon runners. When unset, the workflow falls back to the official `1.1.0-beta.25` SDK.
- `CANGJIE_SDK_WINDOWS_AMD64_URL`
  SDK URL for Windows x64 runners. When unset, the workflow falls back to the official `1.1.0-beta.25` SDK zip package.
- `DEVECO_CANGJIE_OHOS_AARCH64_URL`
  Download URL for the OpenHarmony aarch64 cross-toolchain bundle used as `DEVECO_CANGJIE_HOME`. When unset, the workflow first queries the GitCode tags API and then tries to resolve a matching nightly release asset automatically.
- `CANGJIE_NIGHTLY_TAGS_API`
  Optional. Defaults to `https://api.gitcode.com/api/v5/repos/Cangjie/nightly_build/tags?per_page=100`. Used to resolve the latest nightly tag automatically.
- `CANGJIE_STDX_RELEASE_VERSION`
  Optional. When set, CI prefers the official prebuilt `stdx` bundle in the form `https://gitcode.com/Cangjie/cangjie_stdx/releases/download/v<version>/cangjie-stdx-<platform>-<version>.zip`. When unset, Linux still falls back to source builds while macOS / Windows / OpenHarmony first try the version derived from `CANGJIE_STDX_GIT_REF` and only then fall back to `1.0.0.1`.
- `CANGJIE_STDX_GIT_REF`
  Optional. Defaults to `v1.1.0-beta.25`.
- `CANGJIE_STDX_REPO`
  Optional. Defaults to `https://gitcode.com/Cangjie/cangjie_stdx`.
- `HOMEBREW_TAP_REPO`
  Target tap repository, for example `Celading/homebrew-tap`.
- `HOMEBREW_TAP_BRANCH`
  Optional. Defaults to `main`.
- `IGNITE_GIT_URL`
  Optional. Defaults to `https://gitcode.com/cinyu/ignite-cangjie.git`.
- `LISI_GIT_URL`
  Optional. Defaults to `https://gitcode.com/cinyu/lisi`.
- `JINGUISSL_GIT_URL`
  Optional. Defaults to `https://atomgit.com/cinyu/jinguiSSL`.

## Credentials

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`
- `GITCODE_USERNAME`
- `GITCODE_TOKEN`
- `ATOMGIT_USERNAME`
- `ATOMGIT_TOKEN`
- `HOMEBREW_TAP_TOKEN`

GitCode and AtomGit credentials are only needed when dependency repositories require authentication. Read-only dependencies can leave them unset. `HOMEBREW_TAP_TOKEN` is used to push the generated formula into the tap repository.
If you want OpenHarmony nightly tag auto-discovery to work, configure `GITCODE_TOKEN` as well because the current GitCode tags API requires the `private-token` request header.
GitCode workflows are better treated as shell-oriented project variables or injected environment variables with the same names, instead of assuming GitHub-specific repository variable UX.

## Reuse The Same Script Locally

Once `CANGJIE_HOME` and `CANGJIE_STDX_PATH` are available locally, the same release script can be reused directly:

```bash
./scripts/build_release_target.sh \
  --target x86_64-unknown-linux-gnu \
  --target-dir ./target-release/linux-x86_64 \
  --archive-platform linux-x86_64 \
  --version 0.0.2
```

That command runs `cjpm build --target ...` and then produces:

- `dist/releases/soonlink-core-<version>-<platform>.tar.gz`
- `dist/releases/soonlink-core-<version>-<platform>.zip`

Both bundle formats include:

- the executable
- `web/`
- `config/`
- README / changelog files
- `compose.yaml`
- `compose.release.yaml`
- `.env.example`

## Scripts

- `scripts/install_cangjie_ci.sh`
  Downloads the SDK, resolves or builds `stdx`, and exports CI environment variables.
  - It now handles Windows DLL runtime path exports, Linux/macOS multi-directory runtime library discovery, and falls back from symbolic links to directory copies for `stdx` aliases when runners do not permit symlink creation.
- `scripts/install_ci_prerequisites.sh`
  Shared runner bootstrap script for GitHub and GitCode Linux jobs.
  - It currently supports `apt-get`, `dnf`, and `yum`, which keeps Ubuntu and Euler runners on the same minimal dependency contract.
- `scripts/build_release_target.sh`
  Runs the target build and packaging flow end-to-end.
- `scripts/build_release_bundle.sh`
  Packages an already-built binary with repository assets.
- `scripts/prepare_release_workspace.sh`
  Prepares a clean SoonLink + Ignite + lisi + jinguiSSL workspace in CI and rewrites dependencies into local `path` references.
  - It also drops files such as `cangjie-repo.toml`, `module-resolve.json`, and `module-lock.json` so machine-local path hints do not leak into CI contexts.

## Notes

- Pushing tags such as `0.8.27` or `0.0.5.17` automatically triggers `release-artifacts` and `docker-publish`; once the GitHub Release is published, `homebrew-tap` follows.
- The GitCode tag workflow is intentionally limited to the Linux x86_64 bundle. GitHub remains the primary multi-platform release surface.
- The pushed tag must either match the `cjpm.toml` version exactly or append one extra dotted revision, for example release tag `0.0.2.1` on package version `0.0.2`.
- `linux-aarch64` now uses a native `ubuntu-24.04-arm` runner with an ARM64 SDK so release bundles do not depend on x86_64 Linux SDK layouts that omit `linux_aarch64_cjnative` modules.
- `release-artifacts` now attempts all five default platforms by default and adds a sixth OpenHarmony bundle when the toolchain is available:
  - `linux-x86_64`
  - `linux-aarch64`
  - `darwin-x86_64`
  - `darwin-aarch64`
  - `windows-x86_64`
- GitHub Actions now explicitly opts JavaScript-based actions into the Node 24 runtime via `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`, which removes the current Node 20 deprecation warning path.
- `darwin-x86_64` now runs on `macos-15-intel` instead of the previous `macos-13` label, which had started getting cancelled upstream.
- OpenHarmony nightly tag discovery now prefers the GitCode tags API instead of `git ls-remote`.
- If you want to move to a newer SDK later, repository variables can still override these default download URLs.
- Manual `homebrew-tap` runs now fall back to the current `cjpm.toml` version when `release_tag` is left empty, avoiding the previous empty-value failure.
- Windows is currently limited to `windows-x86_64`. Do not promise Windows ARM64 early until the SDK and stdx layout become reproducible.
