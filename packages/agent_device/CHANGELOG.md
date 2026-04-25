# Changelog

## 0.0.1 (unreleased)

Initial Dart port of `agent-device` (TS upstream). Tracks the porting
phases documented in [`PORTING_PLAN.md`](../../PORTING_PLAN.md) at the
workspace root.

Highlights:

- CLI: `devices`, `snapshot`, `screenshot`, `tap`/`fill`/`swipe`/`scroll`/
  `pinch`/`longpress`/`type`/`focus`, `home`/`back`/`app-switcher`/
  `rotate`, `open`/`close`/`apps`/`appstate`, `clipboard`, selector
  primitives (`press`/`find`/`get`/`is`/`wait`), `ensure-simulator`,
  `install`/`uninstall`/`reinstall`, `logs` (one-shot + streaming),
  `network`, `perf` (CPU% delta on iOS device), `record start/stop`,
  `runner stop`, `replay`/`test` for `.ad` scripts, `session`,
  `completion bash|zsh|fish`.
- Library API: `AgentDevice.open(...)` typed façade over the abstract
  `Backend`; `IosBackend` and `AndroidBackend` subclasses cover what
  each platform supports.
- iOS XCUITest runner bridge with auto-cached cross-invocation runner;
  physical-device support over the CoreDevice IPv6 tunnel.
- `dart compile exe`-friendly: produces a single static native binary
  via `make compile`.

License: see the `LICENSE` file at the workspace root.
