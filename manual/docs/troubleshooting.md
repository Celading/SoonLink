# 问题排查

## 1. `cjpm build` / `cjpm test` 失败

优先检查：

- `CANGJIE_STDX_PATH` 是否正确
- 云端依赖是否能访问，或是否需要切换回本地镜像
- `cjpm.toml` 中 Ignite / lisi 依赖地址是否符合当前构建环境

## 2. 服务启动失败

常见原因：

- `8081` 端口被占用
- `config/soonlink.toml` 格式错误
- 运行目录没有写入 `config/devices.json`、`logs/`、`cache/` 的权限

## 3. Web 能打开但操作失败

优先看：

- `/api/health`
- `/api/session/context`
- 浏览器控制台
- 设备是否已登记、是否处于允许操作的授信状态

## 4. 文件上传或目录任务异常

建议按顺序确认：

1. 目标路径是否存在且可写
2. 当前设备是否可达
3. 任务列表里是否已经返回错误信息
4. `logs/` 下是否有对应运行日志

## 5. CLI / MCP 结果和 Web 不一致

通常先以运行时 API 和 CLI 输出为准，再确认：

- Web 是否读到了最新 `/api/session/context`
- 是否存在旧缓存页面
- 当前节点版本是否已统一到 `0.5.29`
