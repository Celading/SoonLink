# SoonLink API

The SoonLink API surface is easiest to understand in four groups.

## 1. Runtime and Session

- `GET /api/health`
- `GET /api/ready`
- `GET /api/session/context`

Use these for runtime checks and for retrieving the current runtime identity, capabilities, and auth description used by Web or automation clients.

## 2. File System

- `GET /api/fs/list`
- `GET /api/fs/info`
- `GET /api/fs/encoding`
- `GET /api/fs/line`

These endpoints support directory browsing, file metadata lookup, and text-preview helpers.

## 3. Transfer and Tasks

- `POST /api/transfer/chunk/session`
- `PUT /api/transfer/chunk/session/:id/chunks/:index`
- `POST /api/transfer/chunk/session/:id/complete`
- `GET /api/transfer/chunk/files/:fileId`
- `GET /api/tasks`
- `POST /api/tasks`
- `GET /api/tasks/:id`
- `DELETE /api/tasks/:id`

These endpoints cover chunk upload, range download, and the unified task list.

## 4. Devices and Trust Foundations

- `GET /api/devices`
- `POST /api/devices/register`
- `POST /api/devices/:id/trust`
- `POST /api/devices/:id/pairing/pin`
- `POST /api/devices/:id/pairing/confirm`

These cover device registration, trust-state updates, and the PIN-pairing foundation.

## Suggestions

- Let clients consult `/api/session/context` before deciding how to expose features or trust-gated actions.
- Prefer the chunk-transfer APIs over the removed legacy upload/download path.
- For agent and tasker integrations, CLI and MCP are often simpler than hand-assembling raw HTTP flows.
