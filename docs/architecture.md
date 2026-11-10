# Mirmir for Mac — architecture

Design: <https://claude.ai/artifact/JHQsDLQDBmpuFQEyqFuHeB> ·
Product decisions: <https://claude.ai/artifact/KQwehDZuHXFEjDX3qzxqZy>

## Decision: a gRPC client that supervises `mirmir`, not a libmir wrapper

The app is a SwiftUI client of mirmir's private `Runtime` gRPC service
(`Proto/mirmir.proto`). It contains no inference engine. For the local
instance it attaches to a running `mirmir` server or starts one.

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

`InstanceTarget` is `personal | system | socket(path) | remote(address)`.
The app has exactly one current connection; switching the instance in the
sidebar or menu bar switches every screen.

- **Personal** resolves the socket like `mirmir`'s `Paths::discover`:
  `$XDG_RUNTIME_DIR/mirmir`, else `$MIRMIR_STATE_HOME`, `$XDG_STATE_HOME/mirmir`,
  `~/.local/state/mirmir`, then `mirmir.sock`.
- **System** is `/run/mirmir/mirmir.sock`; **socket** is any explicit path.
- **Remote** is stored with its address and shown, but connecting reports that
  the server side (TLS listener, API keys, scopes) is not implemented yet.

Every connection checks `Health.protocol_version` against the client's
protocol (`1`). A mismatch is the *Update needed* state.

## Local server lifecycle

On launch the app connects to the personal socket. If no server answers (no
socket, or a stale socket that refuses connections, which `mirmir serve`
recovers) it starts `mirmir serve` as a child process: a path from settings,
`MIRMIR_BINARY`, the binary bundled at `Mirmir.app/Contents/Helpers/mirmir`,
else `mirmir` on `PATH`.

The server writes to `~/Library/Logs/Mirmir/server.log`, never to pipes, and
the Logs screen tails that file. With pipes, a server that outlived the app
wrote into a closed pipe. Testing then showed a poisoned runtime lock in that
orphaned server. The cause is not proven, but a file sidesteps it, and a
re-attached app still shows the log.

An owned server is stopped with `SIGTERM` (graceful shutdown, 10 s before
`SIGKILL`) on *Pause server* and on quit, including a quit caused by
`SIGTERM`/`SIGINT` to the app. A server started by someone else (CLI, TUI,
launchd) is attached and never stopped by the app.

The gRPC client sets the HTTP/2 `:authority` to `localhost` for Unix sockets.
grpc-swift's default is the socket path, which is not a valid authority, and
tonic rejects it.

Later: an `SMAppService` launch agent so serving survives quitting the app.

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
| Remote instances | — | TLS listener, keys, scopes (product doc, steps 5–7) |

## mirmir issues found while testing the app

- **Two memory sources.** `Telemetry` reports the Metal working-set budget
  (`Metal unified memory`, 55.7 GB on a 64 GB M3 Max); `TelemetryHistory`
  samples host RAM through `sysinfo` (`macOS unified system memory`, 68.7 GB).
  The app labels each value with its `memory_source`. The server should report
  one source, or both explicitly.
- **Residency through a symlinked cache.** With `hf-hub` reached through a
  symlink, `ListLocalModels` lists a restored model as `available` under the
  symlink path while `ListActiveModels` reports it under the resolved path. The
  app treats `ListActiveModels` as authoritative and matches resolved paths.
  The server should canonicalize the paths it compares.

## Build

SwiftPM, macOS 15+ (grpc-swift 2 requires it). `swift build` for development;
`scripts/bundle.sh` assembles `Mirmir.app` with `Info.plist` and, if provided,
the `mirmir` helper binary.
