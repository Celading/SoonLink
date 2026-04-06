# SoonLink 0.5.21

拥有一座私人跨端文件仓库，从未如此简单。

## Highlights

- Core edition baseline is now aligned with the real public boundary: preview-only capabilities are no longer exposed by default.
- The Web console now renders its default edition context as `core`, so visible badges and capability gates match the open-source baseline.
- GitHub Release artifact automation is now in place for Linux and macOS bundles, with Docker publishing defaulting to `linux/amd64` and `linux/arm64`.

## Included

- Core capability-boundary closeout across runtime profile, tests, and Web defaults
- Packaging scripts for reproducible release bundles
- GitHub Actions workflow for release artifacts
- Updated docs for GitHub Actions, troubleshooting, and release preparation

## Upgrade Notes

- If you previously relied on preview-oriented capability defaults in local tests or custom wrappers, refresh them against the current `core` profile.
- Re-check edition badges and capability assumptions in any custom Web embedding.
- Update release and deployment references to `0.5.21`.

## Bundles

- `linux-x86_64`
- `linux-aarch64`
- `darwin-x86_64`
- `darwin-aarch64`

## Checks

- `cjpm test`
- public boundary audit
- GitHub Actions release artifact workflow
