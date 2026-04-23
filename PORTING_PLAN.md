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
- First, fill the verifier-flagged exec gaps: `runCmdDetached` returns `Future<Process>` (caller awaits the spawn, receives a live handle); `runCmdBackground` returns a `({Process process, Future<RunCmdResult> wait})` record matching the TS `ExecBackgroundResult` shape. **Decision (2026-04-23)**: `runCmdDetached` returns `Future<Process>`, not `Future<int>` — closer to TS usage sites and gives the caller full lifecycle control.
- Define `abstract class Backend` matching `src/backend.ts`.
- Port `platforms/android/*`: `adb.ts`, `ui-hierarchy.ts` (XML → SnapshotNode), `devices.ts`, `app-lifecycle.ts`, `input-actions.ts`, `screenshot.ts`, `snapshot.ts`, `install-artifact.ts`, `manifest.ts`, `app-parsers.ts`, `settings.ts`, `perf.ts`, `notifications.ts`, `open-target.ts`, `scroll-hints.ts`, `sdk.ts`, `device-input-state.ts`. ~4050 TS LOC; split into three waves:
  - **Wave A** (foundations): `adb`, `sdk`, `devices`, `manifest`, `app-parsers`, `install-artifact` — standalone utilities.
  - **Wave B** (snapshot layer): `ui-hierarchy`, `snapshot`, `screenshot`, `scroll-hints`.
  - **Wave C** (actions + lifecycle + assembly): `input-actions`, `app-lifecycle`, `device-input-state`, `notifications`, `open-target`, `perf`, `settings`, `index` (the `AndroidBackend` class that implements `Backend`).
- **Integration testing**: mirror the TS `android.yml` workflow — `reactivecircus/android-emulator-runner@v2` on ubuntu-latest (pixel_7, api 36, google_apis_playstore), run `.ad` replay scripts (`test/integration/replays/android/*.ad`) through the Dart CLI. Keep local unit tests pure (parsing ADB output strings, no real subprocess) so `dart test` stays fast; integration tests gate on `AGENT_DEVICE_ANDROID_IT=1` for local dev. CI workflow added in the last step of this phase, after there's something real to test.

### Phase 4 — Runtime + in-process SDK (3 days)

**Design deviation from TS (decision 2026-04-23):** the TS `bindCommands` pattern generates ~40 methods on the runtime via dynamic TypeScript. It doesn't port cleanly to Dart and the resulting `Map<String, Function>` wouldn't be type-safe for SDK consumers. Instead, build a Dart-idiomatic `AgentDevice` class with typed method signatures wrapping the `Backend`. This is the shape other Dart packages will import. The CLI (Phase 5) and `.ad` replay runner (Phase 10) are the stable user-facing contracts; the programmatic API gets a Dart-native shape.

Scope:
- Port `runtime-contract.ts` types (`CommandSessionRecord`, `CommandSessionStore`, `CommandPolicy`, etc.) → `lib/src/runtime/contract.dart`.
- Port memory session store → `lib/src/runtime/session_store.dart`.
- Port minimal device resolution (pick first matching device via `Backend.listDevices`) → `lib/src/runtime/device_resolver.dart`. Full `resolveTargetDevice` with CLI flags lands in Phase 5; for now, programmatic callers pass a simple filter.
- New file (Dart-only): `lib/src/runtime/agent_device.dart` — `AgentDevice` class with typed methods (`open`, `snapshot`, `tap`, `fill`, `openApp`, etc.) that build `BackendCommandContext` with `deviceSerial` resolved from session state, dispatch to `backend.<method>`, and update session state on mutation.
- Defer until needed by Phase 5: `core/dispatch.ts` (906 LOC — this ties together CLI flags, device resolution, batch/series, and replay healing); `core/batch.ts`; `core/interactors.ts` (selector→point resolution — can stay on the Backend side for now via `snapshot+find` rather than a separate interactor registry); `commands/index.ts` catalog metadata.
- Smoke test: rewrite `android_live_test.dart` to use `AgentDevice` instead of raw `AndroidBackend` calls. Proves the programmatic API works end-to-end on a real device.

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
- **Native runner reuse confirmed (2026-04-23)**: the Swift `ios-runner/` project and `macos-helper/` binary are reused as-is via subprocess — no Dart rewrite, no `dart:ffi` bridge. Keep the platform seam thin so a future FFI-backed replacement is possible but don't extract platform-agnostic helpers speculatively.
- **Skills / docs**: the `skills/` directory (agent-operating guidance) ships with the npm package. Decide whether to copy them verbatim into the Dart package or leave upstream.
- **Test execution model**: Node version uses `vitest` for unit + `node --test` for integration. Dart uses `package:test`. Need fixtures + an integration-gated harness; mirror `CONTRIBUTING.md` env vars (`ANDROID_SERIAL`, `IOS_UDID`).

---

## 8. Status / Changelog

- **2026-04-23**: Plan drafted.
- **2026-04-23**: Phase 0 done. Pub workspace at repo root, package at `packages/agent_device` (Dart SDK ^3.11, `args` / `path` / `crypto` / `http` / `shelf` / `shelf_router` / `xml` / `image` / `meta`, dev: `lints` / `test`). Strict analyzer (`strict-casts` / `strict-inference` / `strict-raw-types`). CLI stub at `bin/agent_device.dart` with `--version`; smoke test green; `dart analyze` clean; `dart format` clean. Makefile (`get` / `analyze` / `format` / `test` / `check`) + GH Actions CI on macos-latest.
- **2026-04-23**: Phase 1 partial — ported `utils/errors.ts` + `utils/redaction.ts` (hand) and the 6-file `utils/snapshot*.ts` group (haiku subagent, inline; worktree isolation rejected so review-by-diff). 51 tests passing; analyze clean. Open TODOs: `snapshot/visibility.dart` stubs mobile-surface semantics pending port of `utils/mobile-snapshot-semantics.ts`; `processing.dart::extractNodeReadText` aliases `extractNodeText` pending `text-surface.ts` port.
- **2026-04-23**: Phase 1 continued — selectors (7 files, ~906 Dart LOC) and `.ad` replay parser/serializer (4 files, ~1055 Dart LOC) ported by two haiku subagents. Also ported minimal `PlatformSelector` enum under `lib/src/platforms/`. Replay subagent added a small `SessionRuntimeHints` type (real type from `daemon/types.ts`, verified). 169 tests passing; analyze clean. Decision recorded above: no port of `command-schema.ts` / `args.ts` / `cli-option-*.ts` — switch to `package:args` `Command` classes per command in Phase 5. Phase 1 now substantively complete except for the small `commands/index.ts` catalog metadata, which can wait until Phase 4 (runtime) since it depends on types defined there.
- **2026-04-23**: Phase 2 — exec/png/diagnostics/retry/path_resolution/timeouts ported by two parallel `feature-port-haiku` subagents (~1,480 Dart LOC), then audited by `feature-port-verifier` (sonnet). Verifier caught two real bugs that slipped past analyze/tests: exec null-byte guard used digit-zero `'0'` rather than NUL `\x00`; timeout used SIGTERM instead of SIGKILL. Both fixed in `fe3a0ff` with regression tests for the null-byte case. 272 tests passing. Key Node→Dart divergences: `AsyncLocalStorage` → Dart `Zone` values; `AbortSignal` → custom `CancelToken`; `Process.runSync` has no timeout param so `runCmdSync` silently ignores `timeoutMs` (documented); `runCmdBackground` / `runCmdDetached` stubbed as `NOT_IMPLEMENTED` because Dart's `Process.start` is async — Phase 3 (Android) will force real implementations (plan notes below). `output.ts` deferred — depends on the un-ported `screenshot-diff*.ts` and `mobile-snapshot-semantics.ts` chains.
- **2026-04-23**: Phase 7 done — selector/ref targeting on `AgentDevice` and CLI. Commit `de2a6cf`. Extends the programmatic façade with a sealed `InteractionTarget` hierarchy (`PointTarget` | `RefTarget` | `SelectorTarget`), a `.parseArgs(List<String>)` auto-detecting x-y coords vs `@ref` vs selector expression, plus target-based `tapTarget` / `fillTarget` / `focusTarget` / `longPressTarget` wrappers and four new methods: `find(text)` (substring search over label/value/identifier), `getAttr(attr, target)`, `isPredicate(predicate, target, {expectedText})`, `wait(predicate, target, {timeout, pollInterval})`. CLI gains `press`, `find`, `get`, `is`, `wait` — `is` and `wait` exit 1 on FAIL for shell-pipeline composition. Two real bugs surfaced and fixed: `AndroidBackend.captureSnapshot` returned `RawSnapshotNode`s without calling `attachRefs`, so Phase 1's `findNodeByRef` would never match (threaded `attachRefs` in); `selectors/is_predicates.dart::evaluateIsPredicate` had no `case 'exists':` branch in its switch, making `is exists` always return `pass: false` regardless of match state (fixed + regression test). Test contract also corrected: TS selector syntax is whitespace-AND, not `&&`. Deferred: per-interaction selector *healing* across failed replays (needs Phase 10 replay runner context); disambiguation heuristics for ambiguous matches are already in `resolveSelectorChain` and wired through `_resolveNode`. 11 new unit tests + 9 new live CLI tests on the Pixel 9 Pro emulator (find, get identifier, is exists/visible/editable/text, press @ref, press id=..., wait exists success + timeout). Totals: 542 unit + 14 programmatic/xinv/selector/bbox live + 23 CLI blackbox live = 579 tests green, `dart analyze` clean.
- **2026-04-23**: Phase 6A done — disk-backed session store unlocks cross-invocation state sharing in the CLI. Commit `48279ed`. Design note recorded: the TS `src/daemon/session-store.ts` is actually an in-memory `Map<string, SessionState>` — TS gets cross-invocation sharing through its long-lived daemon process, not from disk. Phase 6A ships a `FileSessionStore implements CommandSessionStore` as a Dart-port-only bridge so users get cross-shell state before Phase 6B (full daemon) lands. Phase 6B will reuse this store inside the daemon. Code (~450 Dart LOC): `runtime/paths.dart` (StatePaths + resolver mirroring TS `daemon/config.ts` file layout: `~/.agent-device/{daemon.json,daemon.lock,daemon.log,sessions/}`), `runtime/file_session_store.dart` (one JSON file per session, per-writer unique `.tmp.<pid>_<hex>` names, `RandomAccessFile.lock(FileLock.exclusive)` on a `.lock` sidecar, atomic rename, corrupt-file tolerance), `cli/base_command.dart` threads session-stored `deviceSerial` into `DeviceSelector` when the user hasn't passed `--serial` / `--device` (so `open` in shell A → `snapshot` in shell B auto-resolves the same device), `--state-dir` + `--ephemeral-session` global flags, `session list/show/clear` subcommands. Bug fixed during validation: `AgentDevice.open` was overwriting the session to `{name, deviceSerial}` on every call — losing the prior `appId`. Now merges via `copyWith`. Tests: 11 unit tests (FileSessionStore, including 8-isolate concurrent write — caught a real race on a shared `.tmp` path) + 6 live cross-invocation tests spawning separate `dart run bin/agent_device.dart` subprocesses and asserting state survives (open→show, snapshot-without-platform, merge-not-clobber, clear, ephemeral, multi-session-name). Totals: 531 unit + 5 AgentDevice live + 23 CLI blackbox live + 6 cross-invocation live = 565. dart analyze clean. Phase 6B (full daemon process + HTTP RPC + lockfile singleton + auto-spawn) is still scoped but deferred until iOS (Phase 8) lands — the daemon's main value-add is amortizing expensive long-lived state like the iOS XCUITest runner, which doesn't exist yet.
- **2026-04-23**: Phase 5 MVP done — working `agent-device` CLI. Commit `9d9ab78` (~800 Dart LOC under `lib/src/cli/`, 18 subcommands). Architecture: each CLI command is a typed `Command` subclass of `AgentDeviceCommand` (which in turn extends `args/command_runner.dart::Command<int>`) that parses its own positionals/flags and drives `AgentDevice`. Shared flags (`--session`, `--platform`, `--serial`, `--device`, `--json`, `--verbose` / `--debug`) live on `AgentDeviceCommand`; global flags at the top-level parser are honored too (either `agent-device --json snapshot` or `agent-device snapshot --json` works). JSON envelope: `{"success": true, "data": ...}` or `{"success": false, "error": {code, message, hint, diagnosticId, logPath, details}}` — matches the TS Node CLI shape. Commands wired: `devices`, `snapshot`, `screenshot`, `open`, `close`, `tap`, `fill`, `type`, `focus`, `back`, `home`, `app-switcher`, `swipe`, `scroll`, `longpress`, `appstate`, `apps`, `clipboard`. Exit codes: 0 ok, 1 error, 64 usage. Validated end-to-end on the Pixel 9 Pro emulator — `devices`/`open`/`snapshot`/`appstate`/`home`/`screenshot` all round-trip correctly in both human and JSON modes; a 179 KB PNG was captured via the CLI. `package:args` replaces the 2100-LOC TS `command-schema.ts` / `args.ts` / `cli-option-*.ts` / `cli-options.ts` chain per the Phase 1 decision. **Deferred** (not blocking for daily use): `batch` command (runs multiple commands in one JSON payload — needs `core/batch.ts` port), `replay` / `test` commands (run `.ad` scripts — Phase 10), `record` / `trace` / `logs` / `network` / `perf` / `diff` observability commands (Phase 10), interactive selector targeting (`agent-device press @e3` style — needs interactor registry from Phase 4 deferred items), `alert`, `rotate`, `pinch`, `press` (the TS "keypress" command). 520 unit tests + 5 live tests passing; analyze clean.
- **2026-04-23**: Phase 4 follow-ups landed (`4729bee`) from verifier audit: `CommandSessionRecord.copyWith` couldn't clear nullable fields — added `clearFields` sentinel set. `closeApp` now actually clears `appId` from session state. `SnapshotState` added to public barrel. `CommandPolicy.maxImagePixels` corrected from fabricated 50M/25M to TS-matching 20M/20M. Removed a spurious `sessions.get` in `getClipboard`. Added Phase-5-required `AgentDevice` wrappers: `pinch`, `pressKey`, `readText`, `findText`, `handleAlert`, `pushFile`, `openSettings`. 516 unit tests.
- **2026-04-23**: Phase 4 done — programmatic runtime façade. Single commit `0df6bbc` (~700 Dart LOC, 15 new unit tests). Shape diverges from the TS `bindCommands` dynamic-dispatch pattern: Dart gets a typed `AgentDevice` class with concrete methods (`open`, `snapshot`, `openApp`, `tap`, `fill`, etc.) that populate `BackendCommandContext.deviceSerial` from session state on every call. Includes `MemorySessionStore`, `CommandSessionRecord` / `CommandSessionStore` / `CommandPolicy` / `CommandClock` / `DiagnosticsSink` types, minimal device resolution (pick first matching via `Backend.listDevices`). Session state mutates on `openApp`/`closeApp`; `closeApp` falls back to the session-stored `appId`. Deferred to Phase 5: full `core/dispatch.ts` (906 LOC — tangles CLI flag resolution with dispatch), `core/batch.ts`, `core/interactors.ts`, `commands/index.ts` catalog. Validation: the live test (`test/platforms/android/android_live_test.dart`) was rewritten to drive `AgentDevice` instead of raw `AndroidBackend`; all 5 tests pass end-to-end on the Pixel 9 Pro emulator — session open, snapshot (51 nodes), screenshot (179 KB PNG), getAppState, listApps, pressHome. 513 unit tests + 5 live tests passing; analyze clean. **This is the "can run simple programmatic tests" milestone** — an SDK consumer can now `import 'package:agent_device/agent_device.dart'` and drive an Android device with ~10 lines of Dart.
- **2026-04-23**: Phase 3 done. exec gap filled — `runCmdDetached` / `runCmdBackground` now return `Future<Process>` / `Future<ExecBackgroundResult>` (Dart async, not TS sync). Backend abstraction (`lib/src/backend/`, 8 files) + cross-platform helpers (`lib/src/core/`, `lib/src/platforms/`) + Android platform (16 files in `lib/src/platforms/android/`) ported across Wave A (foundations), Wave B (snapshot layer), Wave C1 (helpers + light actions), Wave C2 (input_actions + settings), Wave C3 (app_lifecycle + AndroidBackend assembly) — ~7,800 Dart LOC under `lib/src/`. Key architectural decision (**option 3**): `Backend` is `abstract class` with default-throws implementations of every method; only `platform` is abstract. Subclasses override what they support. Mirrors TS's structural `AgentDeviceBackend` type where consumers construct partial objects. `BackendCommandContext` gains a Dart-port-only `deviceSerial` field (Phase 4 runtime populates). `AndroidBackend` wires 25 methods (snapshot/screenshot, tap/fill/typeText/focus/longPress/swipe/scroll, pressBack/pressHome/rotate/openAppSwitcher, clipboard, setKeyboard, openApp/closeApp/getAppState/listApps, triggerAppEvent, listDevices/bootDevice, installApp/reinstallApp); the rest inherit `unsupported`. Wave C3 ran into token-budget issues once and a design issue once; the second attempt + hand-wiring resolved both. feature-port-verifier audited the full phase (`1c035f4..73299f0`) and caught five missed wirings that would have broken Phase 4 command dispatch — all five fixed before closing the phase. 498 tests passing; `dart analyze` clean; zero `dynamic` under `lib/src/`. **Known gaps for Phase 4**: Wave C Android functions take `String serial` instead of TS `DeviceInfo`, so `device.target` (TV vs mobile) branching was dropped (`_resolveAndroidLaunchCategories` always returns mobile — TODO in `app_lifecycle.dart:155`); `.aab` install (`_installAndroidAppBundle`) stubbed as `UnimplementedError` pending bundletool port; Wave C unit tests are shallow (construct-call-only) — deferred to a `withMockedAdb` helper in Phase 4. `commands/index.ts` catalog deferred to Phase 4 where runtime types land.

(Append dated entries below as phases land.)
