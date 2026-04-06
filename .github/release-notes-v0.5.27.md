# SoonLink 0.5.27

拥有一座私人跨端文件仓库，从未如此简单。

## Highlights

- Release automation now accepts plain dotted tags such as `0.8.27` and `0.0.5.17`, without requiring a `v` prefix.
- GitHub Release, Docker publish, and Homebrew tap flows now validate that the pushed tag matches `cjpm.toml`.
- Public Homebrew CI has been stabilized by installing through a temporary tap and fixing the generated wrapper path rendering.

## Included

- Dotted-tag aware GitHub Actions release flow
- Version-alignment guardrails for release metadata and packaged bundle names
- Stable Homebrew local formula validation in public CI
- Version and release references synchronized to `0.5.27`

## Upgrade Notes

- Update package metadata, runtime version references, and public docs to `0.5.27`.
- Use tags such as `0.5.27` or `0.5.27.1` when triggering public release automation.
- Keep the pushed tag aligned with the `cjpm.toml` version in the same commit.

## Bundles

- `linux-x86_64`
- `linux-aarch64`
- `darwin-x86_64`
- `darwin-aarch64`
- `windows-x86_64`

## Checks

- `cjpm test`
- public boundary audit
- GitHub Actions workflow YAML validation
