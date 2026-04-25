# agent-device (Dart)

Dart port of the [`agent-device`](https://github.com/callstackincubator/agent-device) TypeScript CLI for driving mobile UI automation, taking snapshots, capturing logs and video, and running `.ad` replay scripts against iOS and Android devices.

Ships as both:

- a **CLI** (`agent-device` / `ad`) for day-to-day shell use, and
- a **Dart library** (`package:agent_device`) you can import into any
  Dart / Flutter project to drive devices programmatically via
  `AgentDevice.open(...)`.

## Quick start

```bash
# 1. Bootstrap the workspace.
make get
# Or build a standalone native binary:
make compile     # → dist/agent-device  (+ dist/ad symlink)

# 2. (iOS only, one-time per target) Build the XCUITest runner. Needs Xcode.
#    Simulator:
xcodebuild build-for-testing \
  -project ios-runner/AgentDeviceRunner/AgentDeviceRunner.xcodeproj \
  -scheme AgentDeviceRunner \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath ios-runner/build

#    Physical device (needs a provisioning profile for `dev.roszkowski.agentdevice.runner`):
xcodebuild build-for-testing \
  -project ios-runner/AgentDeviceRunner/AgentDeviceRunner.xcodeproj \
  -scheme AgentDeviceRunner \
  -destination "generic/platform=iOS" \
  -derivedDataPath ios-runner/build-device

# 3. Drive a simulator.
xcrun simctl boot "iPhone 17"
dart run packages/agent_device/bin/agent_device.dart \
  devices --platform ios --json

# Optional: shell completions
eval "$(./dist/agent-device completion bash)"      # bash
eval "$(./dist/agent-device completion zsh)"       # zsh
./dist/agent-device completion fish | source       # fish
```

### Physical iOS device prerequisites

To drive a paired iPhone (`--platform ios --serial <UDID>`) the runner
needs to be trusted **on the device itself**, one-time:

1. **Enable Developer Mode** — `Settings → Privacy & Security →
   Developer Mode → On`, then reboot the phone.
2. **Trust the runner certificate** — after the first `xcodebuild
   build-for-testing -destination "generic/platform=iOS"` installs
   `AgentDeviceRunner.app`, open it once from the home screen. You'll
   hit an "Untrusted Developer" sheet; go to `Settings → General →
   VPN & Device Management`, tap your developer profile, and trust it.
3. **Keep the phone unlocked** during test runs.

If any of those are missed you'll see a `COMMAND_FAILED` with hint
"The UI test runner failed to enable automation mode …".

The runner is intentionally cached across CLI invocations (under
`~/.agent-device/ios-runners/<udid>.json`) so subsequent commands skip
the ~14s xcodebuild cold-start. To dismiss the on-device "Automation
Running" overlay, run:

```bash
agent-device runner stop                  # active session's device
agent-device runner stop --serial <UDID>  # specific device
agent-device runner stop --all            # every cached runner
```

Every command takes `--platform ios|android`, `--serial <udid|id>`,
`--session <name>`, and emits either human-readable text or `--json`.
Session state (which device + which app) persists across invocations
under `~/.agent-device/sessions/` so `open` in one shell and `tap` in
another both land on the same device.

## Supported features

| Capability                        | Android                | iOS simulator        | iOS device (devicectl) |
| --------------------------------- | ---------------------- | -------------------- | ---------------------- |
| `devices`                         | ✅                     | ✅                    | ✅                     |
| `snapshot` (accessibility tree)   | ✅                     | ✅ (XCUITest runner) | ✅                     |
| `screenshot` → PNG                | ✅                     | ✅ (simctl)          | ✅                     |
| `tap` / `longpress` / `swipe`     | ✅                     | ✅                    | ✅                     |
| `fill` / `type` / `focus`         | ✅                     | ✅                    | ✅                     |
| `scroll` (direction + amount)     | ✅                     | ✅                    | ✅                     |
| `pinch` (scale + optional center) | ❌ (runner gap)        | ✅                    | ✅                     |
| `home` / `back` / `app-switcher`  | ✅                     | ✅                    | ✅                     |
| `rotate portrait \| landscape-…`  | ✅                     | ✅                    | ✅                     |
| `open <app>` / `close [app]`      | ✅                     | ✅ (simctl)          | ✅ (devicectl)         |
| `apps` / `appstate`               | ✅                     | ✅                    | ✅ (apps only)         |
| `clipboard` get / `--set <text>`  | ✅                     | ✅ (simctl pbpaste/pbcopy) | ❌                  |
| `press` / `find` / `get` / `is` / `wait` — selector/@ref targeting | ✅ | ✅ | ✅ |
| `ensure-simulator <name>`         | n/a                    | ✅                    | n/a                    |
| `logs --since 30s --out <path>` (one-shot) | ✅ (logcat -T)  | ✅ (simctl log show) | ❌ (use `--stream` instead — Apple has no host-side `log show` for devices) |
| `logs --stream --out <path>` / `logs --stop` | ✅ (logcat --pid + cross-invocation PID cache) | ✅ (simctl log stream predicate) | ✅ (idevicesyslog via libimobiledevice) |
| `record start` / `record stop`    | ✅ (screenrecord + pull) | ✅ (XCUITest runner + sandbox pull) | ✅ (runner + `devicectl copy from` — needs device trust + Developer Mode) |
| `perf [--metric cpu\|memory]`      | ✅ (dumpsys)           | ✅ (simctl spawn ps)  | ✅ (xctrace 2× 1s + delta — true CPU%) |
| `network <logPath>` (HTTP from logs) | ✅ (cross-line Android enrichment) | ✅       | ✅                     |
| `install` / `uninstall` / `reinstall` | ✅ (apk + aab)        | ✅ (.app + .ipa)     | ✅ (.app + .ipa via devicectl — needs signed bundle) |
| `replay <script.ad>` / `test <glob>` | ✅                  | ✅                    | ✅                     |
| Self-healing replay (`--replay-update`) | ✅               | ✅                    | ✅                     |
| Per-step artifacts + auto log-dump on failure | ✅           | ✅                    | ❌ (needs logs)         |

### `.ad` replay scripts

A `.ad` file is one command per line, plus an optional leading `context`
header. Example:

```ad
# context is optional; affects per-script retries and platform gate
context platform=ios retries=1 timeout=30000

open com.apple.mobilesafari
snapshot
press id=url-field
fill id=url-field https://example.com
press @e12                 # tap a specific snapshot node ref
wait visible label="Example Domain" 5000
screenshot /tmp/safari.png
record start /tmp/safari.mp4
scroll down --amount=2
record stop /tmp/safari.mp4
close com.apple.mobilesafari
```

Supported actions in the replay runner: `open`, `close`, `home`, `back`,
`app-switcher`, `rotate`, `type`, `swipe`, `scroll`, `longpress`,
`pinch`, `click`/`press`/`tap`, `fill`, `snapshot`, `screenshot`,
`record start/stop`, `appstate`. Selector-backed steps (`click`/`fill`/
`get`/`is`/`wait`) can auto-heal with `--replay-update`: on failure a
fresh snapshot is taken, the selector is re-resolved against the
current tree, the step retried, and the script file rewritten with the
healed selector.

#### Parameters

`.ad` scripts support `${VAR}` interpolation in positional args, flag
values, and runtime hints. Sources, in **decreasing** precedence:

1. `agent-device replay -e KEY=VALUE` (or `--env KEY=VALUE`, repeatable)
2. `AD_VAR_*` shell env (e.g. `AD_VAR_APP=prod` exposes `${APP}`)
3. File-local `env KEY=VALUE` directives at the top of the `.ad` file
4. Built-ins: `${AD_PLATFORM}`, `${AD_SESSION}`, `${AD_FILENAME}`,
   `${AD_DEVICE}`, `${AD_ARTIFACTS}`

Use `${VAR:-default}` for a fallback and `\${...}` to escape. Unresolved
references fail loudly with `file:line`. The `AD_*` namespace is
reserved — only built-ins may use it. `replay --replay-update` cannot
yet round-trip env directives or interpolation tokens, so it refuses
those scripts.

## Library usage

```dart
import 'package:agent_device/agent_device.dart';

final device = await AgentDevice.open(
  backend: const IosBackend(),
  selector: const DeviceSelector(serial: 'UDID-HERE'),
);
await device.openApp('com.apple.mobilesafari');
final snap = await device.snapshot();
print('${snap.nodes?.length ?? 0} nodes');

await device.tap(200, 400);
final logs = await device.readLogs(since: '30s');
for (final entry in logs.entries) {
  print(entry.message);
}
```

`AgentDevice` is a typed façade over the abstract `Backend` — instead
of TS's dynamic `bindCommands`, Dart gets concrete methods on the
façade and `IosBackend` / `AndroidBackend` subclasses fill in what each
platform supports. Everything else inherits an `UNSUPPORTED_OPERATION`
default so partial support is honest.

## Architecture

```
bin/agent_device.dart                CLI entry point (dispatches to cli/run_cli.dart)
│
├── lib/src/cli/                     args-backed commands
│   ├── commands/*.dart              one file per top-level command
│   └── run_cli.dart                 CommandRunner wiring + buildCliRunner()
│
├── lib/src/runtime/                 typed façade (library API) + session store
│   ├── agent_device.dart            AgentDevice.open(...) and per-action methods
│   ├── file_session_store.dart      ~/.agent-device/sessions/<name>.json
│   └── paths.dart                   state-dir resolution
│
├── lib/src/replay/                  .ad script layer
│   ├── script.dart                  parser + serializer + context header
│   ├── replay_runtime.dart          dispatch table + heal + artifact dumper
│   └── heal.dart                    selector re-resolution
│
├── lib/src/selectors/               @ref + DSL (`id=foo`, `role=Button label="OK"`)
├── lib/src/snapshot/                accessibility-tree types + ref attach
├── lib/src/diagnostics/             log_stream_record + network_log (HTTP extractor)
├── lib/src/backend/                 abstract Backend + options / results / capabilities
│
├── lib/src/platforms/android/       adb + screenrecord + logcat + snapshot/input
│                                    + apk/aab install_artifact
│
└── lib/src/platforms/ios/
    ├── runner_client.dart           XCUITest bridge (HTTP POST /command, BSD socket
    │                                on physical devices over CoreDevice tunnel)
    ├── ios_backend.dart             Backend subclass (simctl + runner + devicectl)
    ├── devicectl.dart               physical-device list / launch / install / uninstall
    ├── simctl.dart                  buildSimctlArgs helper
    ├── ensure_simulator.dart        find-or-create + boot
    ├── install_artifact.dart        .app + .ipa (single-app or hint-resolved multi-app)
    ├── app_lifecycle.dart, devices.dart, perf.dart, screenshot.dart
```

The XCUITest runner itself lives at `ios-runner/AgentDeviceRunner/` —
a small Swift project Dart shells out to via `xcodebuild
test-without-building`. See `RunnerBSDSocketServer.swift` /
`RunnerTests+CommandExecution.swift` for the on-device side.

Key design choices vs. the TS source:

- No long-lived daemon. TS spawns one for state sharing; Dart instead
  persists sessions to disk (`~/.agent-device/sessions/`), plus the
  iOS XCUITest runner (`~/.agent-device/ios-runners/<udid>.json`),
  Android screenrecord PID (`~/.agent-device/android-recorders/<serial>.json`),
  and live log streams (`~/.agent-device/log-streams/<deviceId>.json`)
  so CLI invocations and the user's shell both converge on the same
  underlying tooling.
- No dynamic `bindCommands`. `AgentDevice` exposes concrete typed
  methods; each `Backend` subclass overrides what it supports — the
  base class's `unsupported(...)` makes partial coverage honest.
- iOS physical devices route over the CoreDevice IPv6 tunnel
  (`xcrun devicectl device info details → tunnelIPAddress`), not the
  legacy usbmuxd/iproxy path Apple deprecated on iOS 17+.

## Still missing / roadmap

**Phase 9 — desktop platforms** *(not started)*
- macOS (`macos-helper` Swift binary + AX API bridge)
- Linux (`atspi-dump.py`)

**Phase 10 follow-ups** *(observability core + streaming + install is shipped)*
- Android pinch multi-touch (runner gap, not a Dart gap)
- `record --hide-touches` overlay (TS does it as an ffmpeg post-pass
  driven by the runner's gesture-event log — sizeable separate port)
- iOS install from URL sources / nested archives (TS supports trusted
  GitHub Actions + EAS artifact URLs and `.zip`/`.tar.gz` containers
  around the `.app`/`.ipa`; current Dart port handles local paths only)

**Phase 11 — React Native / metro integration** *(not started)*
- `metro.ts` / `metro-companion.ts` / `remote-config*.ts` / `remote-connection-state.ts` port (~1500 LOC of HTTP client + runtime-hint injection). Lets `.ad` scripts bootstrap against a running metro dev server so the launched app loads your current un-bundled JS.
- If the target is **Flutter apps** instead of React Native, this turns
  into a Dart-specific design (VM Service / `flutter attach` /
  hot-reload) rather than a port.

**Phase 12 — polish & release** *(in progress)*
- ✅ `dart compile exe` standalone binary (`make compile` → `dist/agent-device`)
- ✅ Shell completions: `agent-device completion bash|zsh|fish`
- ✅ pub.dev dry-run passes (MIT-licensed; `publish_to: none` stays
  in until you actually want to publish)
- Byte-for-byte CLI output diff against the Node CLI on a `.ad` corpus

## Testing

```bash
# Unit tests (fast, no device required):
dart test packages/agent_device/test \
  --exclude-tags='android-live,ios-live,ios-device-live,android-emulator,fixture-live'

# iOS simulator live suite (needs a booted simulator + built runner):
AGENT_DEVICE_IOS_LIVE=1 dart test --tags=ios-live

# iOS physical device suite (also needs AGENT_DEVICE_IOS_DEVICE_UDID=<udid>):
AGENT_DEVICE_IOS_LIVE=1 AGENT_DEVICE_IOS_DEVICE_UDID=<udid> \
  dart test --tags=ios-device-live

# Android live suite (booted emulator or connected device):
AGENT_DEVICE_ANDROID_LIVE=1 dart test --tags=android-live

# All checks (analyze + unit tests):
make check
```

Test tags in use: `android-live`, `android-emulator`, `ios-live`,
`ios-device-live`, `fixture-live`. Tests without a tag never need a
device.

## License

MIT — see [`LICENSE`](./LICENSE).

---

For the full porting history, design decisions, and phase-by-phase
changelog see [`PORTING_PLAN.md`](./PORTING_PLAN.md).
