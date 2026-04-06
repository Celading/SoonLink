# GitHub Actions / Release

SoonLink Core 已补一套可直接放进 GitHub 的自动化骨架，目标是把“源码构建 / Release 制品 / Docker 多架构镜像”分成三条彼此独立但可复用的链路。

## 工作流

- `.github/workflows/core-ci.yml`
  用于公共边界检查、Compose 校验与基础构建烟测。
- `.github/workflows/release-artifacts.yml`
  用于生成 GitHub Release 制品，默认覆盖：
  - `linux-x86_64`
  - `linux-aarch64`
  - `darwin-x86_64`
  - `darwin-aarch64`
- `.github/workflows/docker-publish.yml`
  用于推送 Docker Hub 镜像，默认平台已收口为：
  - `linux/amd64`
  - `linux/arm64`

## 需要配置的仓库变量

- `CANGJIE_SDK_LINUX_AMD64_URL`
  Linux x86_64 runner 使用的仓颉 SDK 下载地址；同时也作为 `linux-aarch64` 交叉构建宿主 SDK。
- `CANGJIE_SDK_MACOS_AMD64_URL`
  macOS Intel runner 使用的 SDK 下载地址。
- `CANGJIE_SDK_MACOS_ARM64_URL`
  macOS Apple Silicon runner 使用的 SDK 下载地址。
- `CANGJIE_STDX_GIT_REF`
  可选，默认 `v1.1.0-beta.25`。
- `CANGJIE_STDX_REPO`
  可选，默认 `https://gitcode.com/Cangjie/cangjie_stdx`。

## Docker 发布需要的 Secrets

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`
- `GITCODE_USERNAME`
- `GITCODE_TOKEN`
- `ATOMGIT_USERNAME`
- `ATOMGIT_TOKEN`

其中 GitCode / AtomGit 认证仅在依赖仓需要鉴权时使用；若依赖源公开可读，可以留空。

## 本地单条命令复用

只要本地环境已经准备好 `CANGJIE_HOME` 与 `CANGJIE_STDX_PATH`，可以直接复用同一条打包脚本：

```bash
./scripts/build_release_target.sh \
  --target x86_64-unknown-linux-gnu \
  --target-dir ./target-release/linux-x86_64 \
  --archive-platform linux-x86_64 \
  --version 0.5.17
```

这条命令会先执行 `cjpm build --target ...`，再自动生成 `dist/releases/soonlink-core-<version>-<platform>.tar.gz`。

## 目录与脚本

- `scripts/install_cangjie_ci.sh`
  在 CI runner 中下载 SDK、构建 stdx 并注入环境变量。
- `scripts/build_release_target.sh`
  统一执行“按目标构建 + 打包”。
- `scripts/build_release_bundle.sh`
  只负责把已产出的二进制和公开资源打成发布包。

## 备注

- `linux-aarch64` 当前按“x86_64 Linux runner + target triple”方式构建；如果你后续发现某版 nightly 对交叉链支持不稳定，可以把对应 matrix 改成 ARM64 原生 runner。
- Windows 制品这轮没有放进 release workflow，因为当前仓库还没有稳定的 Windows SDK 地址与打包链路。等 Windows target 真正可复现后，再补第五条 matrix 即可。
