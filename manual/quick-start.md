# SoonLink Quick Start

## 1. 获取源码

```bash
git clone https://github.com/Celading/SoonLink.git
cd SoonLink
```

## 2. 构建与测试

```bash
cjpm build
cjpm test
```

## 3. 启动

```bash
./target/release/bin/main
```

默认访问：

- Web：<http://localhost:8081>
- Swagger：<http://localhost:8081/swagger>

## 4. 做第一次验证

```bash
./target/release/bin/main version
./target/release/bin/main devices
./target/release/bin/main fs-list --path /
```

如果这里就失败，请直接看 [问题排查](./docs/troubleshooting.md)。
