# SoonLink API

SoonLink 提供当前服务端接口面，可按六组理解。

## 1. 运行态与会话

- `GET /api/health`
- `GET /api/ready`
- `GET /api/session/context`

## 2. 文件系统

- `GET /api/fs/list`
- `GET /api/fs/info`
- `GET /api/fs/encoding`
- `GET /api/fs/line`

## 3. Lanzig 开放只读面

- `GET /api/lanzig/feed.json`：读取本地 `/lanzig-feed` 目录下的只读 Markdown feed
- `GET /api/lanzig/md/:noteId`：读取单个 Markdown 正文

这一组接口只负责公开 feed 和 Markdown 正文，不包含写回、同步或被动订阅。

## 4. 传输与任务

- `POST /api/transfer/chunk/session`
- `PUT /api/transfer/chunk/session/:id/chunks/:index`
- `POST /api/transfer/chunk/session/:id/complete`
- `GET /api/transfer/chunk/files/:fileId`
- `GET /api/tasks`
- `POST /api/tasks`
- `GET /api/tasks/:id`
- `DELETE /api/tasks/:id`

## 5. 设备与授信

- `GET /api/devices`
- `POST /api/devices/register`
- `POST /api/devices/:id/trust`
- `POST /api/devices/:id/pairing/pin`
- `POST /api/devices/:id/pairing/confirm`

## 6. 增强协同

- `GET /api/relay/jobs`
- `GET /api/relay/jobs/stats`
- `GET /api/relay/jobs/:id/cache`
- `POST /api/relay/jobs/:id/restore`
- `GET /api/relay/rooms`：列出持久化频道窗口
- `GET /api/relay/rooms/:id/messages`：读取频道消息历史
- `POST /api/relay/rooms/:id/messages`：写入本地文字消息，受管理员 / 会话访问策略保护
- `GET /api/relay/channel-adapters`：列出频道适配器
- `POST /api/relay/channel-adapters/localsend/peer-info`：解析 LocalSend `v1/v2/info` 节点信息并返回标准频道 peer 模板，受管理员 / 会话访问策略保护
- `POST /api/relay/channel-adapters/:protocolId/messages`：接收适配器侧文字消息，受管理员 / 会话访问策略保护
- `POST /api/relay/localsend/send`：主动把已有 relay cache 发送到 `http://` LocalSend 节点，受管理员 / 会话访问策略保护
- `GET /api/localsend/v2/info`：LocalSend 兼容节点信息
- `POST /api/localsend/v2/register`：LocalSend register 兼容入口，仅归一化候选 peer，不自动授信
- `POST /api/localsend/v2/prepare-upload`：LocalSend 发文件到 SoonLink 中转站的准备阶段，返回 `sessionId` 与 file token map
- `POST /api/localsend/v2/upload?sessionId=&fileId=&token=`：接收 LocalSend 原始文件 body，缓存为 `RelayJob` 并投影到 `localsend` 频道窗口
- `POST /api/localsend/v2/cancel?sessionId=`：取消 LocalSend 上传会话
- `POST /api/localsend/v2/prepare-download`：把中转站 cache 暴露为 LocalSend 取件会话，可用 `jobId` 限定单个文件
- `GET /api/localsend/v2/download?sessionId=&fileId=&token=`：LocalSend 兼容文件下载
- `GET/PUT /api/favorites`
- `GET/POST /api/whitelist/rules`
- `POST /api/whitelist/rules/toggle`
- `DELETE /api/whitelist/rules`
