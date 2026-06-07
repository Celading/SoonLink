# SoonLinkFull API

SoonLinkFull carries the broadest server-side API surface. It is easiest to read in six groups.

## 1. Runtime and Session

- `GET /api/health`
- `GET /api/ready`
- `GET /api/session/context`

## 2. File System

- `GET /api/fs/list`
- `GET /api/fs/info`
- `GET /api/fs/encoding`
- `GET /api/fs/line`

## 3. Lanzig Open Read-Only Surface

- `GET /api/lanzig/feed.json`: read the local read-only Markdown feed under `/lanzig-feed`
- `GET /api/lanzig/md/:noteId`: read one Markdown body

This surface only publishes the feed and Markdown bodies. It does not include write-back, sync, or passive subscription.

## 4. Transfer and Tasks

- `POST /api/transfer/chunk/session`
- `PUT /api/transfer/chunk/session/:id/chunks/:index`
- `POST /api/transfer/chunk/session/:id/complete`
- `GET /api/transfer/chunk/files/:fileId`
- `GET /api/tasks`
- `POST /api/tasks`
- `GET /api/tasks/:id`
- `DELETE /api/tasks/:id`

## 5. Devices and Trust

- `GET /api/devices`
- `POST /api/devices/register`
- `POST /api/devices/:id/trust`
- `POST /api/devices/:id/pairing/pin`
- `POST /api/devices/:id/pairing/confirm`

## 6. Enhanced Collaboration

- `GET /api/relay/jobs`
- `GET /api/relay/jobs/stats`
- `GET /api/relay/jobs/:id/cache`
- `POST /api/relay/jobs/:id/restore`
- `GET /api/relay/rooms`: list persistent channel windows
- `GET /api/relay/rooms/:id/messages`: read channel message history
- `POST /api/relay/rooms/:id/messages`: write a local text message, protected by the admin / session access policy
- `GET /api/relay/channel-adapters`: list channel adapters
- `POST /api/relay/channel-adapters/localsend/peer-info`: parse LocalSend `v1/v2/info` peer metadata and return a normalized channel peer template, protected by the admin / session access policy
- `POST /api/relay/channel-adapters/:protocolId/messages`: ingest adapter-side text messages, protected by the admin / session access policy
- `POST /api/relay/localsend/send`: actively send an existing relay cache entry to an `http://` LocalSend peer, protected by the admin / session access policy
- `GET /api/localsend/v2/info`: LocalSend-compatible peer info
- `POST /api/localsend/v2/register`: LocalSend register-compatible candidate ingress; it normalizes peers but does not auto-trust them
- `POST /api/localsend/v2/prepare-upload`: prepare LocalSend file upload into the SoonLink relay station and return `sessionId` plus file token map
- `POST /api/localsend/v2/upload?sessionId=&fileId=&token=`: receive the raw LocalSend file body, cache it as a `RelayJob`, and project an event into the `localsend` channel window
- `POST /api/localsend/v2/cancel?sessionId=`: cancel a LocalSend upload session
- `POST /api/localsend/v2/prepare-download`: expose relay cache as a LocalSend download session; `jobId` can restrict the session to one file
- `GET /api/localsend/v2/download?sessionId=&fileId=&token=`: LocalSend-compatible file download
- `GET/PUT /api/favorites`
- `GET/POST /api/whitelist/rules`
- `POST /api/whitelist/rules/toggle`
- `DELETE /api/whitelist/rules`
