# Deployment

The open-source edition currently keeps three common delivery paths.

## 1. Build from Source

```bash
cjpm build
cjpm test
./target/release/bin/main
```

Use this for local development, quick validation, and source-level debugging.

## 2. Docker Compose

For a faster machine-local deployment, the repository already includes:

- `Dockerfile`
- `compose.yaml`
- `scripts/prepare_container_bundle.sh`

Recommended order:

1. produce a runnable binary first
2. prepare the container bundle
3. run `docker compose up --build`

## 3. Homebrew

The repository also keeps the Homebrew formula-rendering and CI-validation path for macOS delivery.

Relevant scripts:

- `scripts/prepare_homebrew_bundle.sh`
- `scripts/render_homebrew_formula.sh`

## Confirm Before Deploying

- `CANGJIE_STDX_PATH` is set correctly
- `config/soonlink.toml` is valid
- `config/devices.json` and the log directory are writable
- port `8081` is not already occupied
