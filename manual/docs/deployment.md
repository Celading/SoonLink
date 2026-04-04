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
- `scripts/prepare_container_bundle.sh`

推荐顺序：

1. 先产出可运行二进制
2. 再准备容器 bundle
3. 最后执行 `docker compose up --build`

## 3. Homebrew

仓库里保留了 Homebrew 公式渲染与 CI 验证链路，适合做 macOS 侧的安装分发。

相关脚本：

- `scripts/prepare_homebrew_bundle.sh`
- `scripts/render_homebrew_formula.sh`

## 部署前确认

- `CANGJIE_STDX_PATH` 正确
- `config/soonlink.toml` 可用
- `config/devices.json` 与日志目录有可写权限
- 端口 `8081` 未被占用
