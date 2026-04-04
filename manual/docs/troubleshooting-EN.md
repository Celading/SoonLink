# Troubleshooting

## 1. `cjpm build` / `cjpm test` fails

Check these first:

- whether `CANGJIE_STDX_PATH` is correct
- whether cloud dependencies are reachable, or whether your environment needs local mirrors instead
- whether the Ignite / lisi dependency sources in `cjpm.toml` match your current build environment

## 2. Service startup fails

Common causes:

- port `8081` is already occupied
- `config/soonlink.toml` is malformed
- the runtime directory cannot write `config/devices.json`, `logs/`, or `cache/`

## 3. The Web UI opens but actions fail

Check these first:

- `/api/health`
- `/api/session/context`
- the browser console
- whether the target device is registered and currently allowed for the requested action

## 4. File upload or directory-task failures

Confirm in order:

1. the target path exists and is writable
2. the current device is reachable
3. the task list already reports an error payload
4. the matching runtime log exists under `logs/`

## 5. CLI / MCP and Web results disagree

Usually trust the runtime API and CLI first, then confirm:

- whether the Web UI has fetched the latest `/api/session/context`
- whether an old browser cache is still in play
- whether the current node is actually running version `0.5.17`
