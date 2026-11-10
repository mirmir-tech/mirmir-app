# Mirmir for Mac

A native macOS app for [mirmir](https://mirmir.tech): always available from the
menu bar, with a window for throughput and memory charts, the model library,
chat, sessions, logs and the instances you manage.

The app is a client of mirmir's `Runtime` gRPC service. On this Mac it attaches
to the running personal server, the one the CLI and TUI use, or starts
`mirmir serve` itself. See [docs/architecture.md](docs/architecture.md) for
why and for the protocol gaps that are still open.

## Requirements

- macOS 15 or later
- Swift 6 toolchain (Xcode 16 or later)
- `mirmir` 0.5.5 or later on `PATH`, or bundled with `--helper`
- `protoc`, only to regenerate the gRPC client

## Build and run

```bash
swift build
swift test
scripts/bundle.sh --helper "$(command -v mirmir)"
open build/Mirmir.app
```

`swift run Mirmir` also works for quick iteration. It runs without a bundle,
so it has no bundle identifier.

## Updating the protocol

```bash
scripts/generate-proto.sh --sync
```

This copies `../mirmir/proto/mirmir.proto` (or `$MIRMIR_PROTO`) and regenerates
`Sources/MirmirRPC/Generated` with plugins built from the resolved package
versions.

## Status

First version: menu bar panel, Overview, Models (inspector, load/unload,
generation defaults, Hugging Face download), Chat with streaming and
reasoning, Instances for local sockets, Sessions, and Logs for the server the
app starts. Remote instances are stored and shown but cannot connect until
mirmir ships its TLS listener and API keys.
