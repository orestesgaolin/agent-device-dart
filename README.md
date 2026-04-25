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
bin/agent_device.dart                 CLI entry point
│
├── lib/src/cli/                     args-backed commands
│   ├── commands/*.dart              devices, snapshot, tap, replay, record, logs, network, …
│   └── run_cli.dart                 CommandRunner wiring
│
├── lib/src/runtime/
│   ├── agent_device.dart            typed façade (library API)
│   ├── file_session_store.dart      ~/.agent-device/sessions/<name>.json
│   └── paths.dart                   state-dir resolution
│
├── lib/src/replay/                  .ad script layer
│   ├── script.dart                  parser + serializer + context header
│   ├── replay_runtime.dart          dispatch table + heal + artifact dumper
│   └── heal.dart                    selector re-resolution
│
├── lib/src/selectors/               @ref + DSL (`id=foo`, `role=Button label="OK"`)
│   ├── parse.dart / resolve.dart / build.dart / match.dart / is_predicates.dart
│
├── lib/src/snapshot/                accessibility-tree types + ref attach
│
├── lib/src/diagnostics/
│   └── network_log.dart             HTTP extractor from app-log dumps
│
├── lib/src/platforms/android/       adb + screenrecord + logcat + snapshot/input wiring
│
├── lib/src/platforms/ios/
│   ├── runner_client.dart           XCUITest bridge (HTTP POST /command)
│   ├── ios_backend.dart             Backend subclass (simctl + runner + devicectl)
│   ├── devicectl.dart               physical-device listing + launch
│   ├── ensure_simulator.dart        find-or-create + boot
│   └── …
│
└── lib/src/backend/                 abstract Backend + options/results
```

Key design choices vs. the TS source:

- No long-lived daemon. TS spawns one for state sharing; Dart instead
  persists sessions to disk (`~/.agent-device/sessions/`), plus the
  iOS XCUITest runner (`~/.agent-device/ios-runners/<udid>.json`) and
  Android screenrecord PID (`~/.agent-device/android-recorders/<serial>.json`)
  so CLI invocations and the user's shell both converge on the same
  underlying tooling.
- No dynamic `bindCommands`. `AgentDevice` exposes concrete typed
  methods; each `Backend` subclass overrides what it supports.

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
- Byte-for-byte CLI output diff against the Node CLI on a `.ad` corpus
- pub.dev publish — dry-run is one `LICENSE` file from passing
  (waiting on a license decision)

## Testing

```bash
# Unit tests (fast, no device required):
dart test packages/agent_device/test --exclude-tags='android-live,ios-live,cli-live'

# iOS live suites (need a booted simulator + built runner):
AGENT_DEVICE_IOS_LIVE=1 dart test --tags=ios-live

# Android live suites (need a booted emulator or connected device):
AGENT_DEVICE_ANDROID_LIVE=1 dart test --tags=android-live
```

## License

Same as upstream `agent-device`.

---

For the full porting history, design decisions, and phase-by-phase
changelog see [`PORTING_PLAN.md`](./PORTING_PLAN.md).
