# GitHub Actions / Release

SoonLink Core 已补一套可直接放进 GitHub 的自动化骨架，目标是把“源码构建 / Release 制品 / Docker 多架构镜像”分成三条彼此独立但可复用的链路。

## 工作流

- `.github/workflows/core-ci.yml`
  用于公共边界检查、Compose 校验与基础构建烟测。
  - 当仓库已配置 `CANGJIE_SDK_LINUX_AMD64_URL` 时，会自动安装 Linux SDK 与 `stdx`，真实执行 `cjpm build`、`cjpm test` 和容器运行包预备。
  - 同时会克隆 `Ignite / lisi / jinguiSSL`，在临时工作副本里把依赖改写为 `path` 后再构建，避免直接依赖当前公开仓的 git 拉取形态。
  - 若仓库变量尚未配置，则会给出 warning，并只保留边界/Compose 这两层校验。
- `.github/workflows/release-artifacts.yml`
  用于生成 GitHub Release 制品，默认覆盖：
  - `linux-x86_64`
  - `linux-aarch64`
  - `darwin-x86_64`
  - `darwin-aarch64`
  - `windows-x86_64`
  - 每个平台默认同时输出 `.tar.gz` 与 `.zip` 两种 bundle，便于直接下载解压。
- `.github/workflows/docker-publish.yml`
  用于推送 Docker Hub 镜像，默认平台已收口为：
  - `linux/amd64`
  - `linux/arm64`
- `.github/workflows/homebrew-tap.yml`
  用于在 Release 发布后，把 Darwin x64 / arm64 两个 bundle 的校验信息渲染进 Homebrew formula，并推送到 tap 仓库。

## 需要配置的仓库变量

- `CANGJIE_SDK_LINUX_AMD64_URL`
  Linux x86_64 runner 使用的仓颉 SDK 下载地址。
- `CANGJIE_SDK_LINUX_ARM64_URL`
  Linux ARM64 runner 使用的仓颉 SDK 下载地址；`linux-aarch64` release bundle 默认走 `ubuntu-24.04-arm` 原生 runner。
- `CANGJIE_SDK_MACOS_AMD64_URL`
  macOS Intel runner 使用的 SDK 下载地址。
- `CANGJIE_SDK_MACOS_ARM64_URL`
  macOS Apple Silicon runner 使用的 SDK 下载地址。
- `CANGJIE_SDK_WINDOWS_AMD64_URL`
  Windows x64 runner 使用的 SDK 下载地址。
- `CANGJIE_STDX_GIT_REF`
  可选，默认 `v1.1.0-beta.25`。
- `CANGJIE_STDX_REPO`
  可选，默认 `https://gitcode.com/Cangjie/cangjie_stdx`。
- `HOMEBREW_TAP_REPO`
  用于 Homebrew Tap 发布的目标仓库，例如 `Celading/homebrew-tap`。
- `HOMEBREW_TAP_BRANCH`
  可选，默认 `main`。

## Docker 发布需要的 Secrets

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`
- `GITCODE_USERNAME`
- `GITCODE_TOKEN`
- `ATOMGIT_USERNAME`
- `ATOMGIT_TOKEN`
- `HOMEBREW_TAP_TOKEN`

其中 GitCode / AtomGit 认证仅在依赖仓需要鉴权时使用；若依赖源公开可读，可以留空。`HOMEBREW_TAP_TOKEN` 则用于向 tap 仓库推送 formula。

## 本地单条命令复用

只要本地环境已经准备好 `CANGJIE_HOME` 与 `CANGJIE_STDX_PATH`，可以直接复用同一条打包脚本：

```bash
./scripts/build_release_target.sh \
  --target x86_64-unknown-linux-gnu \
  --target-dir ./target-release/linux-x86_64 \
  --archive-platform linux-x86_64 \
  --version 0.5.27
```

这条命令会先执行 `cjpm build --target ...`，再自动生成：

- `dist/releases/soonlink-core-<version>-<platform>.tar.gz`
- `dist/releases/soonlink-core-<version>-<platform>.zip`

两个 bundle 都会一起打入：

- 可执行程序
- `web/`
- `config/`
- README / CHANGELOG
- `compose.yaml`
- `compose.release.yaml`
- `.env.example`

## 目录与脚本

- `scripts/install_cangjie_ci.sh`
  在 CI runner 中下载 SDK、构建 stdx 并注入环境变量。
- `scripts/build_release_target.sh`
  统一执行“按目标构建 + 打包”。
- `scripts/build_release_bundle.sh`
  只负责把已产出的二进制和公开资源打成发布包。
- `scripts/prepare_release_workspace.sh`
  在 CI 中准备一份干净的 SoonLink + Ignite + lisi + jinguiSSL 工作副本，并把依赖改写为 `path` 形式。
  - 同时会排除 `cangjie-repo.toml`、`module-resolve.json`、`module-lock.json` 这类本地路径或本机解析缓存文件，避免把私有路径带进 CI 上下文。

## 备注

- 推送形如 `0.8.27`、`0.0.5.17` 的 tag 时，会自动触发 `release-artifacts` 与 `docker-publish`；GitHub Release 发布后，会继续触发 `homebrew-tap`。
- tag 版本必须与当前提交中的 `cjpm.toml` 版本一致，或使用 `cjpm` 三段版本后再追加一个修订号，例如 `0.5.27.1` 对应包版本 `0.5.27`。
- `linux-aarch64` 已改成 `ubuntu-24.04-arm` + ARM64 SDK 的原生构建链，避免 x86_64 Linux SDK 缺失 `linux_aarch64_cjnative` 模块目录时导致 release bundle 缺包。
- `homebrew-tap` 的手动触发现在会在未显式填写 `release_tag` 时自动回退到当前 `cjpm.toml` 版本，不再因为空值回退错误而炸掉。
- Windows 当前只纳入 `windows-x86_64`。ARM64 Windows 还不建议公开承诺，等仓颉 SDK 与 stdx 目录形态稳定后再补第六条 matrix。
