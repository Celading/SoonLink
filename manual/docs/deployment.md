# 部署与分发

SoonLink 开源版当前保留三种常见交付方式：

## 1. 源码构建

```bash
cjpm build
cjpm test
./target/release/bin/main
```

适合本地开发、快速验证与源码调试。

## 2. Docker Compose

如果你想更快落到一台独立机器上，可以使用仓库内已有的容器相关文件：

- `Dockerfile`
- `compose.yaml`
- `compose.release.yaml`
- `.env.example`
- `scripts/prepare_container_bundle.sh`

推荐顺序：

1. 本地源码构建时，先产出可运行二进制
2. 如果要打本地镜像，准备容器 bundle 后执行 `docker compose --env-file .env.example -f compose.yaml up --build`
3. 如果要直接吃 GitHub / Docker Hub 发布物，执行 `docker compose --env-file .env.example -f compose.release.yaml up -d`

## 3. Homebrew

仓库里保留了 Homebrew 公式渲染、CI 校验与 tap 推送链路，适合做 macOS 侧的安装分发。

相关脚本：

- `scripts/prepare_homebrew_bundle.sh`
- `scripts/render_homebrew_formula.sh`

## 部署前确认

- `CANGJIE_STDX_PATH` 正确
- `config/soonlink.toml` 可用
- `config/devices.json` 与日志目录有可写权限
- 端口 `8081` 未被占用
