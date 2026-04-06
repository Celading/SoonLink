# SoonLink CLI 与 MCP 技能手册

## 适用场景

这份技能手册适合三类使用方式：

- 想直接用 `soonlnk` CLI 管理本机或已登记设备。
- 想把 SoonLink 接给 agent / MCP host 做自动化。
- 想在提交 issue 前，把问题压缩成最小可复现链路。

## 一条最稳的使用顺序

如果你刚接手一个 SoonLink Core 节点，推荐按这个顺序确认：

1. `soonlnk version`
2. `soonlnk capabilities`
3. `soonlnk config --config ./config/config.toml`
4. `soonlnk status --config ./config/config.toml`
5. `soonlnk connectors --config ./config/config.toml`

这样可以先确认版本、版本形态、配置是否生效、运行时状态是否正常，以及当前有哪些连接器已经可用。

## CLI 快速片段

### 查看版本与能力

```bash
soonlnk version
soonlnk capabilities
```

这两个命令适合先确认：

- 当前是不是 `core` edition
- 当前版本号是否和 README / release 一致
- 节点是否暴露了你预期的能力标签

### 查看当前配置和运行时

```bash
soonlnk config --config ./config/config.toml
soonlnk status --config ./config/config.toml
```

更适合先看：

- `webPort`
- `rootDir`
- `tempDir`
- `relayEnabled`
- `enableMdns`

如果页面行为和预期不一致，这两条命令通常比先翻前端代码更快。

### 查看设备、任务和连接器

```bash
soonlnk devices --config ./config/config.toml
soonlnk tasks --config ./config/config.toml
soonlnk connectors --config ./config/config.toml
```

按 ID 定位时可以这样查：

```bash
soonlnk devices --id office-node --config ./config/config.toml
soonlnk tasks --id task-123 --config ./config/config.toml
```

### 登记手动设备

```bash
soonlnk register-device \
  --id office-node \
  --name "Office Mac" \
  --ip 192.168.1.20 \
  --port 8081 \
  --scheme http \
  --base-path /soonlink \
  --config ./config/config.toml
```

适合先用于：

- 本地双机联调
- 没有自动发现时的手工接入
- 先验证 SoonLink 节点间互联，再考虑 UI 收口

### 设备授信与 PIN 配对

```bash
soonlnk pair-device-pin --id office-node --config ./config/config.toml
soonlnk confirm-device-pin --id office-node --pin 123456 --config ./config/config.toml
soonlnk trust-device --id office-node --state trusted --config ./config/config.toml
```

更稳的做法是：

1. 先 `pair-device-pin`
2. 再 `confirm-device-pin`
3. 再做真实传输

如果你只是为了排障临时放行，也可以直接 `trust-device`，但长期建议保留 PIN 流程。

### 文件与目录操作

```bash
soonlnk fs-list --device local --path / --config ./config/config.toml
soonlnk fs-info --device local --path /docs/readme.txt --config ./config/config.toml
soonlnk summary --device local --path /source --config ./config/config.toml
soonlnk transfer \
  --source-device local \
  --target-device office-node \
  --file-path /source \
  --target-path /incoming \
  --config ./config/config.toml
```

这里最有用的顺序通常是：

1. `fs-list`
2. `fs-info`
3. `summary`
4. `transfer`

这样可以先确认路径存在、源项是文件还是目录、预计条目数和体积，再开始传输。

## MCP 使用方式

SoonLink Core 当前比较适合 agent 用的 MCP 工具有：

- `soonlink_status`
- `soonlink_capabilities`
- `soonlink_list_devices`
- `soonlink_list_tasks`
- `soonlink_list_connectors`
- `soonlink_register_device`
- `soonlink_remove_device`
- `soonlink_set_device_trust`
- `soonlink_start_device_pin_pairing`
- `soonlink_confirm_device_pin_pairing`
- `soonlink_list_dir`
- `soonlink_get_file_info`
- `soonlink_summarize_path`
- `soonlink_create_transfer_task`

### 推荐的 agent 操作节奏

如果让 agent 帮你做节点间传输，推荐把提示词或 skill 写成这种顺序：

1. 先调用 `soonlink_status`
2. 再调用 `soonlink_capabilities`
3. 再确认 `soonlink_list_devices`
4. 设备不存在时用 `soonlink_register_device`
5. 未授信时先走 PIN 或显式 trust
6. 传输前先 `soonlink_summarize_path`
7. 最后再 `soonlink_create_transfer_task`

这样能减少 agent 一上来就直接发起失败任务的概率。

## 提 issue 前的最小化模板

如果你要给自己或别人提单，建议先带上这几项：

- 当前版本号
- 当前 edition
- 当前命令行
- 源设备 / 目标设备 / 路径
- `status` 输出
- `summary` 输出
- 任务最终状态

只要这几项齐，大多数 SoonLink Core 问题都能更快落位。

## 一句话经验

SoonLink Core 的 CLI 和 MCP 最适合做“先确认真实状态，再做自动化动作”的工作，不适合跳过状态确认直接盲打。
