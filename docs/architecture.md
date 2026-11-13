# Mirmir for Mac — architecture

Design: <https://claude.ai/artifact/JHQsDLQDBmpuFQEyqFuHeB> ·
Product decisions: <https://claude.ai/artifact/KQwehDZuHXFEjDX3qzxqZy>

## Decision: a gRPC client that supervises `mirmir`, not a libmir wrapper

The app is a SwiftUI client of mirmir's private `Runtime` gRPC service
(`Proto/mirmir.proto`). It bundles mirmir (with libmir and MLX) as a separate
helper process, `Contents/Helpers/mirmir`, but its own code never links the
engine. For the local instance it starts the bundled one inside its sandbox.

Embedding `libmir` behind a C ABI was rejected:

1. **One contract for every instance.** Remote servers (CUDA boxes, other
   Macs) are reached through the same `Runtime` service. An in-process engine
   would still need the gRPC path, so the app would carry two implementations
   of every screen.
2. **The server must outlive the window.** Zed, Raycast and `curl` use the
   OpenAI-compatible HTTP endpoint; the CLI and TUI share the same daemon via
   `daemon::connect_or_start` and its lock file. Model residency cannot depend
   on whether a SwiftUI window is open, and two engines would fight over the
   Metal working set.
3. **Fault and memory isolation.** GPU faults, OOM and multi-GB Metal
   allocations stay in the server process. The UI stays responsive and can
   restart the server without restarting itself.
4. **Parity for free.** Catalog search and pull, memory preflight, activity,
   cancellation, telemetry history, configuration and secrets are already in
   mirmir's application layer. A libmir wrapper would re-implement mirmir.
5. **Repository boundaries.** `libmir` owns model execution; application
   concerns belong to `mirmir`. What the UI is missing is a protocol gap, and
   the fix belongs in `mirmir.proto`, where the TUI and remote clients benefit
   too.

The cost is that every number the UI shows must exist in the protocol. Gaps are
listed below and are shown as unavailable rather than invented.

## Layers

| Target | Owns |
| --- | --- |
| `MirmirRPC` | Code generated from `Proto/mirmir.proto` (`scripts/generate-proto.sh`). Never edited by hand. |
| `MirmirKit` | Typed domain (instances, models, telemetry, activity, generation), protocol decoding, the gRPC connection, the local server supervisor, persistent stores and the observable app model. No SwiftUI views. |
| `MirmirApp` | SwiftUI scenes: `MenuBarExtra` panel, main window with sidebar, sheets, theme and the MiRMiR mark. |

Protocol strings (`state`, `kind`, `stage`, `phase`) are decoded into Swift
enums once, in `MirmirKit/Protocol`. Views never compare strings.

## Instances and the connection

`InstanceTarget` is `personal | remote(address)`.
The app has exactly one current connection; switching the instance in the
sidebar or menu bar switches every screen.

- **Personal** is the app's own server. Its socket resolves like `mirmir`'s
  `Paths::discover` (`$XDG_RUNTIME_DIR/mirmir`, else `$MIRMIR_STATE_HOME`,
  `$XDG_STATE_HOME/mirmir`, `~/.local/state/mirmir`, then `mirmir.sock`).
  Under the sandbox `HOME` is the container, whose path grows with the
  account name: with a 32-character name the container socket would be 111
  bytes, past the 103 that Darwin's `sun_path` holds. The sandbox allows
  binding a socket only inside the container, so `SocketPaths.runtimeLink`
  keeps the runtime directory there (`.local/state/mirmir/run`) and reaches
  it through a symlink in the app's per-user directory,
  `confstr(_CS_DARWIN_USER_DIR)` =
  `/var/folders/…/0/tech.mirmir.app/run`, whose length does not depend on
  the account. The app passes that link to its server as `XDG_RUNTIME_DIR`,
  so both name the socket `/var/folders/…/0/tech.mirmir.app/run/mirmir/mirmir.sock`
  (about 90 bytes). It recreates the link before every connect and server
  start. Outside the sandbox (debug runs) nothing changes. A CLI server's or
  the system server's socket is outside the container and refused by the
  sandbox, so neither is an instance kind; reach such a server as a remote
  one.
- **Remote** is a server's TLS listener at `host:port` (default 7443). Every
  call carries `authorization: Bearer mmk_…`; the key lives in the Keychain
  (`CredentialStore`), never in `instances.json`. The certificate is pinned by
  its SHA-256 fingerprint, read without trusting it or sending the key and
  confirmed by the user in Add Server (`RemoteTLS`, NIOSSL's verification
  callback). A different certificate later is *certificate changed*. Without a
  pin the certificate must chain to a system CA.

Remote-access management (`GetRemoteAccess`, `SetRemoteAccess`,
`CreateRemoteKey`, `RevokeRemoteKey`) is served by mirmir only over its local
socket, so the Remote Access sheet always opens its own connection to This
Mac (`RemoteAccessController`).

Every connection checks `Health.protocol_version` against the client's
protocol (`2`). A mismatch is the *Update needed* state.

## Sandbox

Both editions, the Developer ID DMG and the Mac App Store build, are
sandboxed. `Resources/Mirmir.entitlements` grants the app `network.client`
(remote servers, Hugging Face), `network.server` (the HTTP API and the remote
listener), `files.user-selected.read-write` and `files.bookmarks.app-scope`.
The helper is signed with `Resources/MirmirHelper.entitlements`: exactly
`app-sandbox` and `inherit`, as the App Store requires for a bundled
executable, so it runs in the app's sandbox and container.

Model folders (`ModelFolders`) are chosen in an open panel and kept as
security-scoped bookmarks in `model-folders.json`. Access starts when the
store loads, before the server starts, and a child process inherits it; a
granted folder was readable by the server both when granted while it ran and
when granted before it started. A granted Hugging Face cache (a folder with
`models--*`, or its `hub`) is passed as `HF_HUB_CACHE`, mirmir's external hub
cache; changing it restarts the server. Other folders load by path. A
`mirmir` configuration key for model folders is a later step.

Every unary call has a deadline by kind (`CallDeadlines`, `UnaryCall`):
Health 5 s, monitoring (Telemetry, its history, active models) 10 s,
discovery (local models, inspection, remote access status) 15 s, the
Hugging Face search 30 s, and changes 60 s. A missed deadline is
`ConnectionError.timedOut`, which counts as unreachable: a server that
answers Health and then stops answering is dropped and reconnected instead of
leaving the session on stale data, a probe of another instance or Add
Server's test waiting forever. Server-streaming calls (Generate, Load, Pull,
WatchActivity) have no deadline; they end with their stream or when
cancelled.

## Local server lifecycle

On launch the app connects to its socket. If no server answers (no socket, or
a stale socket that refuses connections, which `mirmir serve` recovers) it
starts `Mirmir.app/Contents/Helpers/mirmir serve` as a child process; there is
no other binary. On the first start, when the container has no
`config.toml`, it runs `mirmir config set server.http_bind 127.0.0.1:18080`,
so the app's HTTP API does not collide with a CLI server on 8080.

The server writes to `~/Library/Logs/Mirmir/server.log` in the container,
never to pipes, and
the Logs screen tails that file. With pipes, a server that outlived the app
wrote into a closed pipe. Testing then showed a poisoned runtime lock in that
orphaned server. The cause is not proven, but a file sidesteps it, and a
re-attached app still shows the log.

An owned server is stopped with `SIGTERM` (graceful shutdown, 10 s before
`SIGKILL`) on *Pause server* and on quit, including a quit caused by
`SIGTERM`/`SIGINT` to the app. A server that outlived a crashed app is
attached on the next launch and not stopped.

The gRPC client sets the HTTP/2 `:authority` to `localhost` for Unix sockets.
grpc-swift's default is the socket path, which is not a valid authority, and
tonic rejects it.

Later: an `SMAppService` launch agent so serving survives quitting the app,
and a `mirmir` configuration key listing model folders.

## Protocol gaps (proposed `mirmir.proto` additions)

| UI element | Today | Needed |
| --- | --- | --- |
| Sessions with client names | `WatchActivity` operations (kind, target, stage) | client identity on generate activity |
| GPU memory: weights / K/V / prefix | host total/available, K/V blocks | per-model resident bytes |
| TTFT p50/p95 | last and mean TTFT | percentiles |
| Versus MLX-LM, Benchmarks screen | — | benchmark results RPC |
| Inspector: layers, experts, measured tok/s | memory estimate, settings | architecture facts |
| Inspector: context length, K/V dtype, prefix cache entries | not per model | per-model runtime settings |
| Chat: Thinking toggle, JSON mode | — | `reasoning` mode and response format on `GenerateRequest` |
| Logs for an attached server | — | log stream RPC |
| Pause for an attached server | — | shutdown RPC (Control scope) |

## mirmir issues found while testing the app

- **Two memory sources** (fixed in protocol 2). `Telemetry` reported the Metal
  working set and `TelemetryHistory` host RAM under one free-form label. Now
  `host_memory` and `accelerator_memory` are separate, with a typed
  `AcceleratorMemoryPool`; the app decodes them into `MemoryPool`.
- **Residency through a symlinked cache** (fixed in mirmir 0.6.0).
  `ListLocalModels` now reports canonical paths, the ones `ListActiveModels`
  returns.

## Build

SwiftPM for `MirmirKit`/`MirmirRPC`, `Mirmir.xcodeproj` for the app bundle. The kit needs macOS 15+ (grpc-swift 2); the app needs macOS 27 on Apple silicon, the target of the MLX it bundles. `swift test` for the kit;
`scripts/bundle.sh` builds `Mirmir.app` with `xcodebuild`, embedding, in Debug or when given,
the `mirmir` helper binary.
