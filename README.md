# MiRMiR for Mac

A native SwiftUI app for [MiRMiR](https://mirmir.tech), the native LLM runtime
for Apple Metal and NVIDIA CUDA. It lives in the menu bar and shows live
throughput and memory, the model library, chat, sessions, logs and every
MiRMiR server you use: this Mac or a GPU box across the room.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://mirmir.tech/assets/screenshots/mac-overview-0.6.0-dark-f6ea7fb4.webp">
  <img alt="MiRMiR for Mac overview with live decode and prefill throughput, time to first token, memory and recent generations" src="https://mirmir.tech/assets/screenshots/mac-overview-0.6.0-light-6bf06191.webp">
</picture>

## What it does

- **Menu bar.** The icon shows the decode rate while a model generates. Its
  panel has the loaded model, decode rate with a one-minute sparkline,
  prefill, sessions, prefix cache hits, memory and shortcuts.
- **Overview.** Decode, prefill, time to first token and memory, throughput
  and memory charts over 5 minutes, 1 hour or 24 hours, and recent sessions.
- **Models.** Local checkpoints with `tools`, `think` and `vision` features,
  load and unload, a memory estimate before loading, generation defaults and
  Hugging Face download.
- **Chat.** Streaming replies with the model's reasoning, tokens, decode rate
  and time to first token per reply. Conversations belong to the server they
  were started on.
- **Servers.** Switch between this Mac and remote servers from the sidebar;
  add a server over TLS with a scoped API key, or share this Mac with
  **Remote Access**.

<table>
  <tr>
    <td width="30%"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://mirmir.tech/assets/screenshots/mac-panel-0.6.0-dark-7d0553c0.webp">
  <img alt="The menu bar panel during two generations" src="https://mirmir.tech/assets/screenshots/mac-panel-0.6.0-light-d6bb7dfa.webp">
</picture></td>
    <td><picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://mirmir.tech/assets/screenshots/mac-chat-0.6.0-dark-c8659aef.webp">
  <img alt="Chat with a streamed reply, its reasoning and statistics" src="https://mirmir.tech/assets/screenshots/mac-chat-0.6.0-light-2cccf82d.webp">
</picture></td>
  </tr>
</table>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://mirmir.tech/assets/screenshots/mac-instances-0.6.0-dark-cc29c370.webp">
  <img alt="Instances with this Mac's server, its loaded models and Remote Access" src="https://mirmir.tech/assets/screenshots/mac-instances-0.6.0-light-9a936665.webp">
</picture>

## How it works

The app bundles the MiRMiR runtime (`mirmir` with libmir and MLX) and runs it
as a separate process. Its SwiftUI code links no Rust crate: it is a client of
that runtime's `Runtime` gRPC service, the same service the CLI and TUI use,
so a remote server is driven exactly like the bundled one.

- **This Mac.** The app attaches to the personal server through its Unix
  socket, resolved like `mirmir` does, or starts `mirmir serve` when none
  answers. Quitting stops a server the app started; one you started keeps
  running.
- **Remote servers.** Calls go over HTTP/2 with TLS and carry an API key with
  the `use` or `control` scope, kept in the login Keychain. The server's
  self-signed certificate is shown before the key is sent and pinned on first
  use; a CA-issued certificate is checked against the system roots.
- **One server at a time.** Every screen and the menu bar show the current
  server; switching changes all of them, including the chat list.

See [docs/architecture.md](docs/architecture.md) for the layers and the
protocol gaps that are still open.

## Install

1. [Download MiRMiR for Mac](https://github.com/mirmir-tech/mirmir-app/releases/latest/download/Mirmir-macOS.dmg),
   open the disk image and drag Mirmir to Applications. It is signed and
   notarized and needs macOS 27 or later on Apple silicon.
2. Start Mirmir. It includes the runtime (mirmir 0.6.0 and MLX); the CLI is
   optional and shares its server. Its guide is at
   [docs.mirmir.tech](https://docs.mirmir.tech/getting-started/mac-app.html).

## Requirements for development

- macOS 27 or later on Apple silicon, Xcode 27 or later (Swift 6)
- a Workmir checkout: every build embeds mirmir and MLX built from it
- `protoc`, only to regenerate the gRPC client

## Build and run

Open `Mirmir.xcodeproj` and run the `Mirmir` scheme. It is the only way the
app is built: the app sources (`Sources/MirmirApp`, a synchronized folder, so
new files need no project edits) compile into a real bundle against the
package's `MirmirKit`, with `Resources/Info.plist`, signed for development
with the team's Apple Development certificate (set `DEVELOPMENT_TEAM` to
yours). The
package has no runnable app product on purpose; a bare executable has no
bundle and no helper.

From the command line:

```bash
swift test                      # MirmirKit, also on Linux
scripts/bundle.sh               # build/Mirmir.app via xcodebuild
open build/Mirmir.app
```

Inside a Workmir checkout, the `Embed mirmir helper` build phase
(`scripts/xcode-helper.sh`) runs `cargo build --release --bin mirmir` in
`../mirmir` and embeds the runtime: `Contents/Helpers/mirmir`,
`Contents/Frameworks/MLX.framework` (libmlx with `mlx.metallib` in its
Resources) and `libjaccl.dylib`, relinked to `@rpath` and signed with the
app's identity and hardened runtime. The app then needs nothing installed and
starts a server matching its protocol. From a
clean checkout it first installs the MLX release pinned in
`../scripts/mlx/version.env` (via `scripts/mlx/setup.sh`, outside Xcode's
build environment) when `.native/mlx` does not point at it. It needs
`rustup`, `cmake`, `ninja` and the Metal toolchain, and says which is missing.
`MIRMIR_HELPER=skip` turns it off (the app then uses `mirmir` from `PATH`)
and `MIRMIR_CARGO_PROFILE=dev` builds an unoptimized server.

Every screen has `#Preview`s on sample data from `AppModel.preview(_:)`
(connected, generating, starting server, offline). Previews never connect,
start mirmir or write `instances.json` and `chats.json`.

## Updating the protocol

```bash
scripts/generate-proto.sh --sync
```

This copies `../mirmir/proto/mirmir.proto` (or `$MIRMIR_PROTO`) and regenerates
`Sources/MirmirRPC/Generated` with plugins built from the resolved package
versions.

## Notes

`MirmirKit` also builds and tests on Linux, without the SwiftUI app target.

Releases: [docs/release.md](docs/release.md).
