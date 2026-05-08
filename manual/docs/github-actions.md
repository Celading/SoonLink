# GitHub / GitCode CI 与 Release

SoonLink 现在同时维护 GitHub 与 GitCode 两套自动化入口：

- GitHub 负责完整的多平台 Release、Docker 和 Homebrew 发布链。
- GitCode 负责贴近仓库主线的 Linux CI 与 tag Linux bundle 组装，目录固定在 `.gitcode/workflows/`。

这样可以把“仓库校验”和“完整跨平台制品发布”分层处理，避免把所有发布责任都压在同一平台上。

## GitHub Workflows

- `.github/workflows/core-ci.yml`
  用于仓库边界检查、Compose 校验与基础构建烟测。
  - 当仓库已配置 `CANGJIE_SDK_LINUX_AMD64_URL` 时，会自动安装 Linux SDK 与 `stdx`，真实执行 `cjpm build`、`cjpm test` 和容器运行包预备。
  - 若配置 `CANGJIE_STDX_RELEASE_VERSION`，会优先下载对应版本的官方预打包 `stdx` release；未配置时，Linux 继续回退到源码构建，而 macOS / Windows / OpenHarmony 任务会优先尝试与 `CANGJIE_STDX_GIT_REF` 对齐的 release 版本，必要时再回退到 `1.0.0.1`。
  - 同时会克隆 `Ignite / lisi / jinguiSSL`，在临时工作副本里把依赖改写为 `path` 后再构建，避免直接依赖当前仓库的 git 拉取形态。
  - 若仓库变量尚未配置，则会给出 warning，并只保留边界/Compose 这两层校验。
  - 同时已加入可选的 `OpenHarmony aarch64` 交叉构建烟测：当 Linux SDK 可用，且 `DEVECO_CANGJIE_OHOS_AARCH64_URL` 已配置或能从 GitCode nightly 自动解析到可达地址时，会额外执行一次 `aarch64-linux-ohos` 构建。
- `.github/workflows/release-artifacts.yml`
  用于生成 GitHub Release 制品，默认覆盖：
  - `linux-x86_64`
  - `linux-aarch64`
  - `darwin-x86_64`
  - `darwin-aarch64`
  - `windows-x86_64`
  - 当 OpenHarmony 工具链可解析时，会追加：
    - `ohos-aarch64`
  - 若已配置 `CANGJIE_STDX_RELEASE_VERSION`，release 打包会直接复用指定版本的官方 `stdx` 预构建包；若未配置，macOS / Windows / OpenHarmony 会先尝试与 `CANGJIE_STDX_GIT_REF` 对齐的 release 版本，必要时再回退到 `1.0.0.1`。
  - 每个平台默认同时输出 `.tar.gz` 与 `.zip` 两种 bundle，便于直接下载解压。
  - 每个平台 job 先产出并上传制品，再统一由 Ubuntu `publish` job 收拢并写入 GitHub Release，避免 macOS / Windows runner 直接上传 release asset 时的差异。
- `.github/workflows/version-package.yml`
  用于在主线版本号推进时自动产出一轮预览打包制品。
  - 触发方式为推送到 `main` / `core`，且本次提交修改了 `cjpm.toml`，或命中了 release bundle 相关 workflow / script。
  - 该 workflow 复用 `release-artifacts.yml` 的多平台打包矩阵，但固定 `publish_release=false`，因此不会自动创建 GitHub Release，也不会触发 Docker / Homebrew 发布。
  - 产物会作为当前 workflow 的 artifact 上传，适合“改版本号后先拿一轮可下载包验收”，再决定是否推正式 tag。
- `.github/workflows/docker-publish.yml`
  用于推送 Docker Hub 镜像，默认平台已收口为：
  - `linux/amd64`
  - `linux/arm64`
- `.github/workflows/homebrew-tap.yml`
  用于在 Release 发布后，把 Darwin x64 / arm64 两个 bundle 的校验信息渲染进 Homebrew formula，并推送到 tap 仓库。

## GitCode Workflows

- `.gitcode/workflows/core-ci.yml`
  用于 GitCode Euler runner 上的主线校验。
  - runner 使用 GitCode 默认的 `euleros-2.10.1`。
  - 通过 `checkout-action@0.0.1` 拉取代码后，在 `repo_workspace` 中执行。
  - 会先做仓库边界审计，再安装 Linux 构建依赖、下载仓颉 SDK / `stdx`、克隆 `Ignite / lisi / jinguiSSL`，最后在临时投影工作副本中执行 `cjpm build` 与 `cjpm test`。
  - Compose 校验仅在 runner 自带 `docker compose` 时执行；若 GitCode runner 未提供 Docker，会打印 warning 而不是让整个 CI 假失败。
- `.gitcode/workflows/release-linux.yml`
  用于 GitCode 上的 tag Linux bundle 组装。
  - 触发方式为手动触发，或推送 `x.y.z` / `x.y.z.n` 形式的 tag。
  - 当前只产出 `linux-x86_64` 的 `.tar.gz` 与 `.zip`，并在 `dist/gitcode-release/` 下补一份 `SHA256SUMS`。
  - 这条链路优先解决“GitCode 远端可验证、可复跑、可看到 tag 制品组装日志”，而不是替代 GitHub 的完整多平台 Release 发布。

## 需要配置的变量与凭据

- `CANGJIE_SDK_LINUX_AMD64_URL`
  Linux x86_64 runner 使用的仓颉 SDK 下载地址。
  - GitHub `core-ci` 若未配置会跳过真实构建。
  - GitCode workflow 若未配置，会回退到当前默认的 `1.1.0-beta.25` Linux x64 SDK 下载地址。
- `CANGJIE_SDK_LINUX_ARM64_URL`
  Linux ARM64 runner 使用的仓颉 SDK 下载地址；`linux-aarch64` release bundle 默认走 `ubuntu-24.04-arm` 原生 runner。
- `CANGJIE_SDK_MACOS_AMD64_URL`
  macOS Intel runner 使用的 SDK 下载地址。未配置时，默认回退到官方 `1.1.0-beta.25` SDK。
- `CANGJIE_SDK_MACOS_ARM64_URL`
  macOS Apple Silicon runner 使用的 SDK 下载地址。未配置时，默认回退到官方 `1.1.0-beta.25` SDK。
- `CANGJIE_SDK_WINDOWS_AMD64_URL`
  Windows x64 runner 使用的 SDK 下载地址。未配置时，默认回退到官方 `1.1.0-beta.25` SDK zip 包。
- `DEVECO_CANGJIE_OHOS_AARCH64_URL`
  OpenHarmony aarch64 交叉构建所需的 `DEVECO_CANGJIE_HOME` 工具链包地址。若未显式配置，workflow 会先调用 GitCode tags API 再尝试按 nightly release 规则自动解析。
- `CANGJIE_NIGHTLY_TAGS_API`
  可选，默认 `https://api.gitcode.com/api/v5/repos/Cangjie/nightly_build/tags?per_page=100`。用于自动获取最新 nightly tag。
- `CANGJIE_STDX_RELEASE_VERSION`
  可选。若配置，会优先下载 `https://gitcode.com/Cangjie/cangjie_stdx/releases/download/v<version>/cangjie-stdx-<platform>-<version>.zip` 形式的官方预打包 `stdx`。未配置时，Linux 继续走源码构建，而 macOS / Windows / OpenHarmony 会先尝试与 `CANGJIE_STDX_GIT_REF` 对齐的 release 版本，必要时再回退到 `1.0.0.1`。
- `CANGJIE_STDX_GIT_REF`
  可选，默认 `v1.1.0-beta.25`。
- `CANGJIE_STDX_REPO`
  可选，默认 `https://gitcode.com/Cangjie/cangjie_stdx`。
- `HOMEBREW_TAP_REPO`
  用于 Homebrew Tap 发布的目标仓库，例如 `Celading/homebrew-tap`。
- `HOMEBREW_TAP_BRANCH`
  可选，默认 `main`。
- `IGNITE_GIT_URL`
  可选，默认 `https://gitcode.com/cinyu/ignite-cangjie.git`。
- `LISI_GIT_URL`
  可选，默认 `https://gitcode.com/cinyu/lisi`。
- `JINGUISSL_GIT_URL`
  可选，默认 `https://atomgit.com/cinyu/jinguiSSL`。

## 凭据

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`
- `GITCODE_USERNAME`
- `GITCODE_TOKEN`
- `ATOMGIT_USERNAME`
- `ATOMGIT_TOKEN`
- `HOMEBREW_TAP_TOKEN`

其中 GitCode / AtomGit 认证仅在依赖仓需要鉴权时使用；若依赖源可直接读取，可以留空。`HOMEBREW_TAP_TOKEN` 则用于向 tap 仓库推送 formula。
若你希望 OpenHarmony nightly tag 自动解析生效，当前 GitCode tags API 还需要 `private-token` 请求头，因此建议同步配置 `GITCODE_TOKEN`。
GitCode workflow 本身不会直接读取 GitHub 风格的 repository variables 页面；它更适合从 GitCode 项目变量或手动注入环境变量中读取同名值。

## 本地单条命令复用

只要本地环境已经准备好 `CANGJIE_HOME` 与 `CANGJIE_STDX_PATH`，可以直接复用同一条打包脚本：

```bash
./scripts/build_release_target.sh \
  --target x86_64-unknown-linux-gnu \
  --target-dir ./target-release/linux-x86_64 \
  --archive-platform linux-x86_64 \
  --version 0.5.56
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
  在 CI runner 中下载 SDK、解析或构建 `stdx` 并注入环境变量。
  - 已支持优先使用官方 `stdx` release 包；并补了 Windows DLL 运行时路径导出、Linux/macOS 的多目录 runtime lib 搜索，以及 `stdx` alias 的复制回退逻辑，避免不同 runner 因符号链接、动态库搜索路径或 release 版本不匹配而炸掉。
- `scripts/install_ci_prerequisites.sh`
  给 GitHub / GitCode 共用的基础 runner 依赖安装脚本。
  - 已支持 `apt-get`、`dnf`、`yum` 三类 Linux 包管理器，主要用于 Euler runner 与 Ubuntu runner 的最小公共依赖准备。
- `scripts/build_release_target.sh`
  统一执行“按目标构建 + 打包”。
- `scripts/build_release_bundle.sh`
  只负责把已产出的二进制和仓库资源打成发布包。
- `scripts/prepare_release_workspace.sh`
  在 CI 中准备一份干净的 SoonLink + Ignite + lisi + jinguiSSL 工作副本，并把依赖改写为 `path` 形式。
  - 同时会排除 `cangjie-repo.toml`、`module-resolve.json`、`module-lock.json` 这类本地路径或本机解析缓存文件，避免把私有路径带进 CI 上下文。

## 备注

- 推送到 `main` / `core` 且 `cjpm.toml` 版本发生变更，或打包工作流自身发生调整时，会自动触发 `version-package`，先产出一轮多平台预览制品；这条链路不会自动发布 GitHub Release。
- 推送形如 `0.8.27`、`0.5.56.1` 的 tag 时，会自动触发 `release-artifacts` 与 `docker-publish`；GitHub Release 发布后，会继续触发 `homebrew-tap`。
- 如果你希望“版本号一次 action 打包”恢复到日常习惯，推荐流程是：先改 `cjpm.toml` 版本并合主线，等待 `version-package` 产出 artifact；确认无误后，再推同版本 tag 触发正式 Release / Docker / Homebrew。
- GitCode 的 tag workflow 当前只收口到 Linux x86_64 bundle，完整多平台资产仍以 GitHub Release 为主发布面。
- tag 版本必须与当前提交中的 `cjpm.toml` 版本一致，或使用 `cjpm` 三段版本后再追加一个修订号，例如 `0.5.56.1` 对应包版本 `0.5.56`。
- `linux-aarch64` 已改成 `ubuntu-24.04-arm` + ARM64 SDK 的原生构建链，避免 x86_64 Linux SDK 缺失 `linux_aarch64_cjnative` 模块目录时导致 release bundle 缺包。
- `release-artifacts` 现在默认会尝试五个平台，并在 OpenHarmony 工具链可用时追加第六个平台：
  - `linux-x86_64`
  - `linux-aarch64`
  - `darwin-x86_64`
  - `darwin-aarch64`
  - `windows-x86_64`
- GitHub Actions 已显式打开 `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`，用来提前规避 2026 年的 Node 20 action 运行时退场告警。
- `darwin-x86_64` 已从旧的 `macos-13` runner 切到 `macos-15-intel`，用来规避此前 Intel macOS job 被平台侧取消的问题。
- OpenHarmony 的 nightly tag 现在优先通过 GitCode API 拉取，而不是依赖 `git ls-remote`。
- 若你后续想切到更新 SDK，可继续用 repository variables 覆盖默认下载地址。
- `homebrew-tap` 的手动触发现在会在未显式填写 `release_tag` 时自动回退到当前 `cjpm.toml` 版本，不再因为空值回退错误而炸掉。
- Windows 当前只纳入 `windows-x86_64`。ARM64 Windows 还不建议提前承诺，等仓颉 SDK 与 stdx 目录形态稳定后再补第六条 matrix。
