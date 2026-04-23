# agent-device → Dart Port: Plan

Source: `agent-device/` (TypeScript, ~116K LOC, Node >=22).
Target: a Dart package usable as (a) a CLI (`agent-device` / `ad`) and (b) a library consumable by other Dart packages. Same command surface, same `.ad` replay format, compatible wire protocol where practical.

Keep this document up to date — edit phases, add decisions/risks, check off work as it lands.

---

## 1. Goals & Non-Goals

Goals
- Match the public CLI surface of `agent-device` — same subcommands, flags, exit codes, JSON shape.
- Run `.ad` replay scripts with the same semantics (metadata `context` header, line-per-action grammar).
- Expose a Dart library API analogous to the Node `createAgentDevice` / `createAgentDeviceClient` / `commands` / `backend` surface so other Dart packages can drive devices programmatically.
- Preserve daemon session model (open → interact → close) and replay/heal semantics.
- Keep parity on core platforms: iOS (simulator + device), Android, macOS, Linux. tvOS treated as an iOS variant.

Non-goals (initial)
- Rewriting the Swift iOS XCUITest runner (`ios-runner/`) or the Swift `macos-helper` — these are already standalone subprocesses invoked by the Node daemon; the Dart port reuses those binaries as-is.
- Rewriting the Python AT-SPI bridge (`src/platforms/linux/atspi-dump.py`) — invoked as a subprocess; ship and call it unchanged.
- 1:1 byte-compatibility of the daemon wire format with the Node daemon. We pick a compatible JSON RPC shape but do not guarantee the Dart daemon and Node CLI interoperate.
- Website / marketing / skill docs. The `skills/` tree is interesting (agent guidance) but not required for feature parity; port later if requested.

---

## 2. Current Architecture (source of the port)

One paragraph per layer. File paths are under `agent-device/src/` unless noted.

- **CLI** (`bin.ts`, `cli.ts`, `cli/commands/router.ts`, `utils/args.ts`, `utils/command-schema.ts`, `utils/cli-options.ts`): argv parse → resolve flags → optionally materialize remote config → send to daemon (auto-spawn if missing) → format JSON or human output.
- **Daemon client transport** (`daemon-client.ts`): HTTP and Unix/TCP socket to local daemon; lock-file `~/.agent-device/daemon.lock`, info file `~/.agent-device/daemon.json` (port, token, signature). Auto-spawns `node bin/agent-device.mjs --daemon` on demand.
- **Daemon** (`daemon.ts`, `daemon/http-server.ts`, `daemon/transport.ts`, `daemon/server-lifecycle.ts`, `daemon/session-store.ts`, `daemon/request-router.ts`): dual-mode (HTTP or net socket) JSON RPC. Sessions persisted to `~/.agent-device/sessions/<name>.json`. ~78 handler files under `daemon/handlers/` decomposed by concern (session lifecycle, snapshot, interaction, find, record-trace, replay, perf, observability).
- **Runtime / in-process API** (`runtime.ts`, `core/dispatch.ts`, `core/capabilities.ts`, `core/interactors.ts`): the same command set, executed in-process against a `Backend`, bypassing daemon. Used by SDK consumers and by the daemon itself.
- **Backend abstraction** (`backend.ts`): ~40 methods (snapshot, screenshot, tap, swipe, scroll, type, fill, install, keyboard, clipboard, logs, network, perf, recording, alert, shell …). Platform modules under `platforms/{ios,android,linux}` + macOS helpers under `platforms/ios/macos-*.ts` implement it.
- **Client library** (`client.ts`, `client-*.ts`, `index.ts`): typed facade over the daemon transport (or in-process runtime). Public SDK; sub-path exports: `./commands`, `./backend`, `./io`, `./artifacts`, `./metro`, `./remote-config`, `./install-source`, `./android-apps`, `./contracts`, `./selectors`, `./finders`.
- **Selectors / snapshots** (`daemon/selectors*.ts`, `utils/snapshot*.ts`, `utils/selector-*.ts`): snapshot tree model, selector DSL (parse/resolve/match/heal), snapshot diff, visibility, ref-vs-selector rules.
- **`.ad` replay** (`daemon/handlers/session-replay*.ts`, `daemon/handlers/session-test*.ts`, `daemon/handlers/session-open-script.ts`): text-based script grammar — `context platform=<p> timeout=<ms> retries=<n>` metadata, `#` comments, then one action per line (`open ...`, `snapshot -i`, `click "selector"`, `tap x y`, etc.). Runner supports per-test retries, artifacts under `.agent-device/test-artifacts/`.
- **Native binaries** (NOT in `src/`):
  - `ios-runner/AgentDeviceRunner/` — Swift Xcode project, XCUITest-based TCP server for gesture/snapshot on iOS/tvOS/macOS simulator and device.
  - `macos-helper/` — Swift Package providing `agent-device-macos-helper` binary for macOS desktop accessibility snapshots.
  - `src/platforms/linux/atspi-dump.py` — Python AT-SPI introspection subprocess.
- **External tools spawned** (`utils/exec.ts` wraps): `adb`, `xcrun simctl`, `xcrun devicectl`, `swift`, `xcodebuild`, `python3`, `ffmpeg`-style recording via platform tools.
- **NPM deps**: only `fast-xml-parser` (plist/XML) + `pngjs` (screenshot diff pixel ops). Everything else is Node built-ins.

Client commands (canonical list — `src/client-command-registry.ts`):
`alert, appstate, app-switcher, apps, back, batch, boot, click, clipboard, devices, diff, fill, find, focus, get, home, is, keyboard, logs, longpress, network, perf, pinch, press, push, record, replay, rotate, scroll, screenshot, settings, snapshot, swipe, test, trace, trigger-app-event, type, wait`.

---

## 3. Target Dart Layout

Repo: `agent-device-dart/` (sibling of `agent-device/` source). Will be a pub workspace.

```
agent-device-dart/
  pubspec.yaml                     # workspace root (or single package for v0)
  packages/
    agent_device/                  # main library + CLI (`dart pub global activate`)
      bin/
        agent_device.dart          # CLI entry (argv -> runCli)
      lib/
        agent_device.dart          # public export (mirrors src/index.ts)
        src/
          cli/                     # CLI parsing, help, routing  (mirrors src/cli.ts, utils/args.ts)
          runtime/                 # in-process runtime  (mirrors src/runtime.ts, core/)
          client/                  # daemon client facade (mirrors src/client.ts)
          backend/                 # Backend abstract class (mirrors src/backend.ts)
          commands/                # command catalog + implementations (mirrors src/commands/)
          daemon/                  # daemon process + handlers (mirrors src/daemon/)
          platforms/
            ios/                   # simctl/devicectl/runner-client
            android/               # adb + UIAutomator XML
            macos/                 # macos-helper subprocess wrapper
            linux/                 # atspi-dump.py wrapper
          selectors/               # selector DSL  (mirrors src/daemon/selectors*.ts + src/utils/selector-*.ts)
          snapshot/                # snapshot model + diff + processing
          replay/                  # .ad parser + test runner
          utils/                   # exec, errors, diagnostics, png, xml, etc.
      test/
      native/                      # bundled Swift/Python assets (copied from agent-device/)
    agent_device_testing/          # optional: conformance + fixtures (mirrors testing/)
```

Key packaging decisions to revisit:
- Ship `ios-runner/`, `macos-helper/`, `atspi-dump.py` in `packages/agent_device/native/` so the CLI can locate them by a path relative to the Dart entry script.
- Daemon process: same Dart binary re-entered with `--daemon` (just like Node's `bin.ts`).

---

## 4. Dependency Mapping (Node → Dart)

| Node / npm | Dart equivalent | Notes |
|---|---|---|
| `node:fs`, `node:fs/promises` | `dart:io` | Direct. |
| `node:path` | `package:path` | Direct. |
| `node:child_process` spawn | `dart:io` `Process.start` / `Process.run` | Streaming stdout/stderr fine. Need helper parity with `utils/exec.ts`. |
| `node:http` server | `package:shelf` + `package:shelf_router` | Tiny surface — daemon RPC is one POST handler. |
| `node:http` client | `package:http` or `dart:io` `HttpClient` | `HttpClient` keeps deps minimal. |
| `node:net` (Unix sockets / TCP) | `dart:io` `ServerSocket` / `RawSocket` | Unix sockets via `InternetAddress.unix`. |
| `node:crypto` | `dart:math` + `package:crypto` | For tokens. |
| `node:url` | `dart:core` `Uri` | Direct. |
| `node:stream` | `dart:async` `Stream` | Direct conceptual mapping. |
| `node:events` EventEmitter | `StreamController` | Direct. |
| `pngjs` | `package:image` | Pixel diff + region rendering. Consider FFI to libpng only if `image` too slow. |
| `fast-xml-parser` | `package:xml` | Plist parsing may need small helper layered on top. |
| `AbortSignal.timeout` | `Future.timeout` / `CancelableOperation` | |
| `JSON.stringify/parse` | `dart:convert` `jsonEncode/jsonDecode` | |
| Node `process.argv/env/exit` | `Platform.environment`, `Platform.executableArguments`, `exit()` | |
| `pathToFileURL` | `Uri.file` | |
| Node lock/single-instance via flock-like | `File.openSync(mode: WRITE)` + advisory lock via `RandomAccessFile.lock` | `dart:io` supports `lock()`. |

Dart-only considerations:
- Isolates for CPU-heavy PNG diff if it becomes a bottleneck.
- `dart:ffi` deferred — only needed if we replace `macos-helper` with in-process accessibility calls (not planned).

---

## 5. Phased Delivery

Each phase should compile, pass its own tests, and leave the repo in a green state. Phase ordering reflects dependency — don't start phase N+1 before N is landed.

### Phase 0 — Scaffolding & tooling (0.5 day)
- Create `agent-device-dart/packages/agent_device` with `pubspec.yaml`, Dart SDK constraint, analyzer/lints config.
- Wire `dart format`, `dart analyze`, `dart test` via a top-level `Makefile` / `justfile` / `melos.yaml`.
- CI skeleton (GH Actions).
- Commit.

### Phase 1 — Pure-Dart foundations (3–5 days)
No process spawning, no network. Types + parsing + formatters.
- Port `utils/errors.ts` → `lib/src/utils/errors.dart` (`AppError`, normalization, codes).
- Port `utils/snapshot.ts`, `utils/snapshot-tree.ts`, `utils/snapshot-visibility.ts`, `utils/snapshot-lines.ts`, `utils/snapshot-processing.ts`, `utils/snapshot-diff.ts` → `lib/src/snapshot/*`.
- Port `utils/selector-*.ts` + `daemon/selectors*.ts` (parse/match/resolve, no IO side) → `lib/src/selectors/*`.
- Port `.ad` parser + writer (`daemon/handlers/session-replay-script.ts`, `session-open-script.ts`) → `lib/src/replay/script.dart`.
- ~~Port command schema + arg parser~~ **Skipped.** `utils/command-schema.ts` (1589 LOC) + `utils/args.ts` + `utils/cli-option-schema.ts` + `utils/cli-options.ts` exist to feed a custom TS arg parser. In Dart we use `package:args` with per-command `Command` subclasses that declare flags inline — that work happens in Phase 5 as each CLI command is ported. The shared universal flags (`--session`, `--platform`, `--json`, `--verbose` / `--debug`, `--state-dir`, etc.) live on a base `Command` class. Net deleted: ~2100 LOC of data-shaped code.
- Port `commands/index.ts` catalog metadata → `lib/src/commands/catalog.dart`. Downstream SDK consumers rely on `commandCatalog` for docs/LSP; this is separate from CLI arg parsing and still needs a small port (data only, no logic).
- Snapshot test fixtures: load a handful of real `.ad` scripts and snapshot JSON samples; assert equivalence with Node outputs.
- **Subagent strategy**: delegate each file's port to a haiku agent in isolation (`isolation: worktree`) with the source file + target path; review and merge.

### Phase 2 — Exec + platform primitives (3 days)
- Port `utils/exec.ts` (`runCmd`/`runCmdSync`) → `lib/src/utils/exec.dart`. This is a hard rule from `AGENTS.md` — everything spawns through it.
- Port `utils/png.ts` → `lib/src/utils/png.dart` using `package:image`.
- Port `utils/redaction.ts`, `utils/retry.ts`, `utils/path-resolution.ts`, `utils/timeouts.ts`, `utils/output.ts`, `utils/version.ts`.
- Port `utils/diagnostics.ts` (scopes, emit, flush) → `lib/src/utils/diagnostics.dart`.

### Phase 3 — Backend interface + Android first (5–7 days)
Pick Android as the first real backend (simplest external dep: just `adb`).
- Define `abstract class Backend` matching `src/backend.ts`.
- Port `platforms/android/*`: `adb.ts`, `ui-hierarchy.ts` (XML → SnapshotNode), `devices.ts`, `app-lifecycle.ts`, `input-actions.ts`, `screenshot.ts`, `snapshot.ts`, `install-artifact.ts`, `manifest.ts`, `app-parsers.ts`, `settings.ts`, `perf.ts`, `notifications.ts`, `open-target.ts`, `scroll-hints.ts`, `sdk.ts`, `device-input-state.ts`.
- Smoke test: `snapshot`, `tap`, `open` against an emulator via an end-to-end integration test (gated on `ANDROID_SERIAL`).

### Phase 4 — Runtime + in-process SDK (3 days)
- Port `core/dispatch.ts`, `core/capabilities.ts`, `core/dispatch-*.ts`, `core/interactors.ts`, `core/batch.ts`, `core/*.ts`.
- Port `runtime.ts` → `createAgentDevice({ backend, sessionStore, policy, clock, diagnostics })`.
- Port `core/session-surface.ts` + `daemon/session-store.ts` (memory + disk) → `lib/src/runtime/session_store.dart`.
- Wire Android backend into a programmatic test: create session → open → snapshot → click → close, no daemon involved.

### Phase 5 — CLI (no daemon yet) (3 days)
- Wire `bin/agent_device.dart` → parse argv → dispatch locally through the in-process runtime (single-shot execution, sessions in-memory for now).
- Port `utils/output.ts` (JSON + human formatters), `cli/commands/*.ts`.
- Port update-notifier as no-op stub initially (`utils/update-check.ts`).
- Produce a usable CLI for Android, even without the daemon. All of `snapshot`, `click`, `fill`, `type`, `scroll`, `back`, `home`, `screenshot`, `open`, `close` should work.
- Parity test: run the same `.ad` script in Node and Dart; compare JSON output.

### Phase 6 — Daemon + transport (4 days)
- Port `daemon-client.ts`, `daemon.ts`, `daemon/http-server.ts`, `daemon/transport.ts`, `daemon/server-lifecycle.ts`, `daemon/config.ts`, `daemon/request-router.ts`, `daemon/response.ts`.
- Implement lockfile + info file with the same filenames under `~/.agent-device/` so both Node and Dart daemons are mutually exclusive (not interoperable, just non-colliding — pick a different port or fail fast if Node daemon detected).
- Port the session-lifecycle handlers under `daemon/handlers/session*.ts`.
- Now `agent-device open` / `close` / `snapshot` all round-trip through a Dart daemon process.

### Phase 7 — Interaction + selector handlers (4 days)
- Port `daemon/handlers/interaction*.ts`, `find.ts`, `snapshot*.ts`, `is-predicates.ts`, `action-utils.ts`, `selector*.ts` (the handler side — parse/resolve/heal).
- Replay heal: `session-replay-heal.ts`.
- Batch runner: `handlers/session-batch.ts`.

### Phase 8 — iOS backend + runner bridge (6–8 days)
- Port `platforms/ios/` (simctl, devicectl, plist, xml, apps, devices, screenshot, perf).
- Port `platforms/ios/runner-client.ts`, `runner-transport.ts`, `runner-contract.ts`, `runner-session.ts`, `runner-xctestrun.ts` — TCP client to existing Swift `ios-runner/` binary.
- Reuse the existing Swift project as-is (build via `xcodebuild`); Dart just drives it.
- `ensure-simulator` command.

### Phase 9 — macOS + Linux (3 days)
- macOS: wrap `macos-helper` binary (Swift); port `macos-apps.ts`, `macos-helper.ts`.
- Linux: wrap `atspi-dump.py`; port `platforms/linux/*`.

### Phase 10 — Replay test runner, record/trace, observability (4 days)
- `daemon/handlers/session-test*.ts`, `session-replay*.ts`, `record-trace*.ts`, `app-log*.ts`, `network-log.ts`, `recording-*.ts`, `upload.ts`, `artifact-*.ts`.
- `test` command: glob of `.ad` files with retries, per-test artifacts under `.agent-device/test-artifacts/`.

### Phase 11 — Metro + remote-config + connection (3 days)
- `metro*.ts`, `remote-config*.ts`, `remote-connection-state.ts`, `cli/commands/connection*.ts`, `install-source*.ts`. React-Native specific; lower priority but needed for parity.

### Phase 12 — Polish, docs, release (2 days)
- Update-notifier, `--version`, `--help`, shell completions.
- Cross-check CLI output byte-for-byte with Node on a suite of `.ad` scripts (per-platform).
- Publish to pub.dev (internal dry-run first).
- Compiled binaries via `dart compile exe` per-OS.

Rough total: **~6–8 engineering weeks** for single-developer parity port; realistically longer given surface area. Plan to release Android + CLI + daemon first (through Phase 7) as an MVP, then stabilize with iOS.

---

## 6. Subagent Workflow

The user asked for subagents (cheaper models) to chip away at discrete tasks. Template:

```
Agent({
  description: "Port <file> to Dart",
  subagent_type: "general-purpose",
  model: "haiku",                        # cost-control; bump to sonnet if complex
  isolation: "worktree",                 # safer for parallel tasks
  prompt: """
    Task: port `agent-device/src/<path>.ts` to
    `agent-device-dart/packages/agent_device/lib/src/<dest>.dart`.

    Source file: <path>
    Dependencies already ported: <list module paths>
    Target API: preserve exported names (snake_case → dart style).
    Do NOT port tests; write a thin smoke test that compiles.
    Keep semantics identical. Flag open questions in a `// TODO(port):` comment.

    Run: `dart analyze packages/agent_device` and `dart format` before finishing.
    Report: new files created, any semantic ambiguity, and tests added.
  """,
})
```

Rules for subagent dispatch:
- One file (or one tight module group) per subagent. No porting of `daemon/handlers/` en masse.
- **Always pass the list of already-ported dependencies** so the agent imports the Dart versions, not re-ports them.
- Verify each subagent's output with `Read` + `dart analyze` before accepting; don't trust the summary.
- Use `isolation: "worktree"` for any port that touches more than one file — easier rollback.
- Use `model: "haiku"` by default for mechanical translations; escalate to `sonnet` for logic-heavy files (selector engine, replay heal, dispatch).

Parallelism: files within the same phase whose dep graphs don't overlap can be ported in parallel — e.g. phase 1 utilities (errors, snapshot-tree, png) are independent.

---

## 7. Risks & Open Questions

- **CLI flag parity**: `utils/command-schema.ts` encodes hundreds of flags. Hand-porting is error-prone; consider a code-gen step that reads the TS AST (via `tsc --emit` to JSON or a simple grep). Decide before Phase 1.
- **Selector engine correctness**: the selector DSL + healing logic is subtle. Plan a fixture-based equivalence suite: run the Node selector engine on a corpus of snapshots and selectors, capture results as JSON, replay the same corpus against Dart.
- **PNG diff performance**: `package:image` is pure Dart and may be 5–10× slower than `pngjs`. Budget a benchmark; fall back to FFI if needed.
- **Daemon interop with Node**: decided NOT to interop. The two implementations detect each other via the shared lockfile and refuse to start concurrently.
- **iOS runner protocol drift**: the Swift `ios-runner/` wire protocol is not versioned. Pin to a specific `ios-runner/` build and document it in the port. Rebuild Swift only when the Dart port supports it.
- **Skills / docs**: the `skills/` directory (agent-operating guidance) ships with the npm package. Decide whether to copy them verbatim into the Dart package or leave upstream.
- **Test execution model**: Node version uses `vitest` for unit + `node --test` for integration. Dart uses `package:test`. Need fixtures + an integration-gated harness; mirror `CONTRIBUTING.md` env vars (`ANDROID_SERIAL`, `IOS_UDID`).

---

## 8. Status / Changelog

- **2026-04-23**: Plan drafted.
- **2026-04-23**: Phase 0 done. Pub workspace at repo root, package at `packages/agent_device` (Dart SDK ^3.11, `args` / `path` / `crypto` / `http` / `shelf` / `shelf_router` / `xml` / `image` / `meta`, dev: `lints` / `test`). Strict analyzer (`strict-casts` / `strict-inference` / `strict-raw-types`). CLI stub at `bin/agent_device.dart` with `--version`; smoke test green; `dart analyze` clean; `dart format` clean. Makefile (`get` / `analyze` / `format` / `test` / `check`) + GH Actions CI on macos-latest.
- **2026-04-23**: Phase 1 partial — ported `utils/errors.ts` + `utils/redaction.ts` (hand) and the 6-file `utils/snapshot*.ts` group (haiku subagent, inline; worktree isolation rejected so review-by-diff). 51 tests passing; analyze clean. Open TODOs: `snapshot/visibility.dart` stubs mobile-surface semantics pending port of `utils/mobile-snapshot-semantics.ts`; `processing.dart::extractNodeReadText` aliases `extractNodeText` pending `text-surface.ts` port.
- **2026-04-23**: Phase 1 continued — selectors (7 files, ~906 Dart LOC) and `.ad` replay parser/serializer (4 files, ~1055 Dart LOC) ported by two haiku subagents. Also ported minimal `PlatformSelector` enum under `lib/src/platforms/`. Replay subagent added a small `SessionRuntimeHints` type (real type from `daemon/types.ts`, verified). 169 tests passing; analyze clean. Decision recorded above: no port of `command-schema.ts` / `args.ts` / `cli-option-*.ts` — switch to `package:args` `Command` classes per command in Phase 5. Phase 1 now substantively complete except for the small `commands/index.ts` catalog metadata, which can wait until Phase 4 (runtime) since it depends on types defined there.

(Append dated entries below as phases land.)
