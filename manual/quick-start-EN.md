# SoonLink Quick Start

## 1. Get the source

```bash
git clone https://github.com/Celading/SoonLink.git
cd SoonLink
```

## 2. Build and test

```bash
cjpm build
cjpm test
```

## 3. Run

```bash
./target/release/bin/main
```

Default entrypoints:

- Web: <http://localhost:8081>
- Swagger: <http://localhost:8081/swagger>

## 4. Do a first validation

```bash
./target/release/bin/main version
./target/release/bin/main devices
./target/release/bin/main fs-list --path /
```

If this already fails, jump straight to [Troubleshooting](./docs/troubleshooting-EN.md).
