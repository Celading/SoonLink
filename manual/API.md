# SoonLink API

SoonLink 当前核心接口可按下面四组理解。

## 1. 运行态与会话

- `GET /api/health`
- `GET /api/ready`
- `GET /api/session/context`

用于检查服务状态、获取当前能力 / auth 描述，以及让前端或自动化端决定能力呈现。

## 2. 文件系统

- `GET /api/fs/list`
- `GET /api/fs/info`
- `GET /api/fs/encoding`
- `GET /api/fs/line`

用于目录浏览、文件元信息读取与文本预览辅助。

## 3. 传输与任务

- `POST /api/transfer/chunk/session`
- `PUT /api/transfer/chunk/session/:id/chunks/:index`
- `POST /api/transfer/chunk/session/:id/complete`
- `GET /api/transfer/chunk/files/:fileId`
- `GET /api/tasks`
- `POST /api/tasks`
- `GET /api/tasks/:id`
- `DELETE /api/tasks/:id`

用于分块上传、Range 下载以及统一任务列表管理。

## 4. 设备与授信基础

- `GET /api/devices`
- `POST /api/devices/register`
- `POST /api/devices/:id/trust`
- `POST /api/devices/:id/pairing/pin`
- `POST /api/devices/:id/pairing/confirm`

用于设备登记、信任状态切换与 PIN 配对基础流程。

## 建议

- 页面接入优先走 `/api/session/context` 判断能力与授信状态。
- 文件传输优先使用分块接口，不再依赖旧上传下载路径。
- 如果你在做 agent / tasker 集成，CLI 与 MCP 往往比直接拼 HTTP 更省事。
