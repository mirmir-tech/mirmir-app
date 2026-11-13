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
- `mirmir` 0.6.0 or later on `PATH` (protocol 2), or bundled with `--helper`
  for local testing
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

0.6.0: menu bar panel, Overview, Models (inspector, load/unload, generation
defaults, Hugging Face download), Chat with streaming and reasoning,
Instances, Sessions, and Logs for the server the app starts.

Remote servers connect over TLS with a scoped API key kept in the Keychain.
Add Server shows the server's certificate fingerprint before sending the key
and pins it on first use; CA-issued certificates are verified against the
system roots instead. This Mac's Remote Access sheet turns its listener on,
creates and revokes keys, and lists recent clients. See mirmir's
[remote access guide](https://github.com/mirmir-tech/mirmir/blob/main/docs/remote-access.md).

`MirmirKit` also builds and tests on Linux, without the SwiftUI app target.

Releases: [docs/release.md](docs/release.md).
