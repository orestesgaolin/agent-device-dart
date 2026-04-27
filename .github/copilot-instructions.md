# Copilot Instructions

## What This Repo Is

Dart port of the TypeScript [`agent-device`](https://github.com/callstackincubator/agent-device) CLI/library for mobile UI automation. Ships as both:
- A CLI (`agent-device` / `ad`) for driving iOS/Android devices from a shell
- A Dart library (`package:agent_device`) for programmatic device control

The TypeScript source lives in `agent-device/` (read-only reference). All Dart code lives in `packages/agent_device/`.

## Build, Test, Lint

```bash
make get          # dart pub get
make analyze      # dart analyze
make format       # dart format .
make test         # dart test packages/agent_device (unit tests only)
make check        # analyze + test
```

**Run a single test file:**
```bash
dart test packages/agent_device/test/selectors/parse_test.dart
```

**Run unit tests only (no device required):**
```bash
dart test packages/agent_device/test --exclude-tags='android-live,ios-live,cli-live'
```

**Live tests (require a running device/emulator):**
```bash
AGENT_DEVICE_IOS_LIVE=1 dart test --tags=ios-live
AGENT_DEVICE_ANDROID_LIVE=1 dart test --tags=android-live
```

CI runs: `dart format --set-exit-if-changed`, `dart analyze`, then `dart test packages/agent_device`.

## Architecture

```
packages/agent_device/
├── bin/agent_device.dart         CLI entry point
├── lib/
│   └── src/
│       ├── cli/commands/         CLI subcommand implementations
│       ├── runtime/
│       │   ├── agent_device.dart typed façade (library API — AgentDevice class)
│       │   ├── file_session_store.dart  ~/.agent-device/sessions/<name>.json
│       │   └── paths.dart
│       ├── backend/              abstract Backend + options/results/capabilities
│       ├── platforms/
│       │   ├── ios/              IosBackend: simctl + XCUITest runner + devicectl
│       │   └── android/          AndroidBackend: adb + screenrecord + logcat
│       ├── selectors/            selector DSL: parse → resolve → build → match
│       ├── snapshot/             accessibility-tree types + @ref attachment
│       ├── replay/               .ad script parser + replay runtime + heal logic
│       └── diagnostics/          network log HTTP extractor
└── test/                         mirrors lib/src/ structure; live tests in platforms/
```

**Key design differences from the TypeScript source:**
- No long-lived daemon. State persists to disk: sessions in `~/.agent-device/sessions/`, iOS runner state in `~/.agent-device/ios-runners/<udid>.json`, Android recorder PIDs in `~/.agent-device/android-recorders/<serial>.json`.
- No dynamic `bindCommands`. `AgentDevice` exposes concrete typed methods; each `Backend` subclass overrides what it supports. Unsupported methods return `UNSUPPORTED_OPERATION` by default.
- `IosBackend` / `AndroidBackend` are the two concrete `Backend` subclasses.

## Key Conventions

**Linter rules** (`analysis_options.yaml`):
- `strict-casts`, `strict-inference`, `strict-raw-types` enabled
- `unused_import`, `unused_local_variable`, `dead_code` are errors
- `prefer_single_quotes`, `require_trailing_commas`, `prefer_const_constructors`

**Module size:** Target ≤ 300 LOC per implementation file. If a file exceeds 500 LOC, extract focused submodules before adding new behavior.

**Backend capabilities:** New platform feature support must go through `BackendCapabilityName` enum in `lib/src/backend/capabilities.dart` — do not add ad-hoc capability strings.

**Selectors:** All selector parsing/matching lives in `lib/src/selectors/`. Pipeline is `parse → resolve → act → record selectorChain → heal on replay`. Do not inline selector logic in handlers.

**Error handling:** Normalize user-facing failures via `lib/src/utils/errors.dart`. Preserve `hint`, `diagnosticId`, `logPath` when wrapping/rethrowing.

**Process execution:** Use the shared exec utilities in `lib/src/utils/`; do not spawn processes inline in command handlers.

**Test tags:** Live tests use `@Tags(['ios-live'])` or `@Tags(['android-live'])` and are gated by environment variables. Unit tests need no tags.

**Commit messages:** Use conventional prefixes: `feat:`, `fix:`, `chore:`, `perf:`, `refactor:`, `docs:`, `test:`, `build:`, `ci:`.

## Selector DSL

Selectors follow a key=value DSL (e.g., `role=button label="Submit"`) with fallback chains (`||`). `@ref` targets a specific accessibility tree node by its attached ref ID. The `parse → resolve → build → match` pipeline in `lib/src/selectors/` is the single source of truth — do not duplicate matching logic elsewhere.

## iOS Runner

The XCUITest runner (`ios-runner/`) is a separate Swift binary invoked over HTTP (`POST /command`). `runner_client.dart` handles command execution and retry; it caches the runner process across CLI invocations to avoid the ~14s cold-start. Do not make `runner_client.dart` import from transport internals.

## .ad Replay Scripts

One command per line. Optional leading `context` header (`context platform=ios retries=1 timeout=30000`). Self-healing replay (`--replay-update`) re-resolves selectors against a fresh snapshot on failure and rewrites the script file. Parser, runtime, and healer live in `lib/src/replay/`.
