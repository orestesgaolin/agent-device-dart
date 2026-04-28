# agent_device

Agent-driven CLI and Dart library for mobile UI automation, accessibility
snapshots, network/log/perf observability, video recording, and `.ad`
replay scripts on iOS and Android.

## Install

```bash
# CLI (global activation)
dart pub global activate agent_device

# Library (add to pubspec.yaml)
dart pub add agent_device
```

The CLI installs two executables: `agent-device` and `ad` (short alias).

## How it works

`agent_device` talks to real iOS simulators/devices and Android
emulators/devices through their native toolchains:

- **iOS**: an XCUITest runner (Swift) launched via `xcodebuild
test-without-building`. Auto-built from bundled source on first use.
- **Android**: `adb` for interactions + a bundled snapshot helper APK
  (13 KB Java instrumentation) that provides multi-window accessibility
  snapshots. Auto-installed on first use.

No emulator images, test frameworks, or additional SDKs are required
beyond Xcode (iOS) and Android SDK (Android).

## CLI quickstart

```bash
# List all connected/booted devices
ad devices

# Capture the accessibility tree
ad snapshot --platform ios --serial <UDID>

# Interact
ad open com.example.myapp --platform android
ad tap 200 400
ad type "hello world"
ad click 'text="Submit"'
ad swipe 200 600 200 200

# Assertions
ad is visible 'text="Welcome"'
ad is hidden 'id=loadingSpinner'
ad wait visible 'text="Done"' --timeout 10000

# Replay an .ad script
ad replay flow.ad --platform ios

# Record video with chapter markers per step
ad replay flow.ad --record recording.mp4
```

Every command supports `--json` for machine-readable output and
`--verbose` for diagnostic logging.

## Library usage

```dart
import 'package:agent_device/agent_device.dart';

void main() async {
  // Open a session on a connected device
  final device = await AgentDevice.open(
    backend: const IosBackend(),
    selector: const DeviceSelector(serial: 'BOOTED-UDID'),
  );

  // Launch an app and capture the UI tree
  await device.openApp('com.example.myapp');
  final snap = await device.snapshot();
  for (final node in (snap.nodes ?? []).whereType<SnapshotNode>()) {
    print('@${node.ref} [${node.type}] ${node.label ?? ""}');
  }

  // Interact via selectors
  await device.tapTarget(
    InteractionTarget.selector('text="Sign In"'),
  );
  await device.typeText('user@example.com');

  // Assert visibility with viewport-aware checks
  final result = await device.isPredicate(
    'visible',
    InteractionTarget.selector('id=welcomeBanner'),
  );
  print('visible: ${result.pass}');

  // Record video with chapters (for test suites)
  final recorder = TestRecorder(device, '/tmp/test.mp4');
  await recorder.start();
  recorder.chapter('login flow');
  // ... test steps ...
  await recorder.stop(); // injects MP4 chapters via ffmpeg

  await device.close();
}
```

### Key classes

| Class                           | Purpose                                                          |
| ------------------------------- | ---------------------------------------------------------------- |
| `AgentDevice`                   | Main facade — open sessions, capture snapshots, interact, assert |
| `IosBackend` / `AndroidBackend` | Platform implementations                                         |
| `DeviceSelector`                | Filter devices by serial, name, or platform                      |
| `InteractionTarget`             | Target a node by `@ref`, selector expression, or x/y coordinates |
| `TestRecorder`                  | Record video with chapter markers in Dart test files             |
| `BackendSnapshotResult`         | Snapshot result with typed node tree                             |

### Selector DSL

Target nodes using a concise selector language:

```dart
// By accessibility identifier
InteractionTarget.selector('id=loginButton')

// By label text (quote spaces)
InteractionTarget.selector('text="Sign In"')

// Compound selectors
InteractionTarget.selector('role=button text="Submit"')

// Fallback chains (try first, then second)
InteractionTarget.selector('id=submit || text="Submit"')

// By @ref from a previous snapshot
InteractionTarget.ref('@e5')
```

## .ad replay scripts

Text-based scripts for repeatable UI flows:

```
context platform=ios
open com.example.myapp
snapshot -i
click 'text="Get Started"'
wait visible 'id=onboardingComplete' 10000
type "Jane Doe"
screenshot ./screenshots/onboarding.png
```

Run with `ad replay flow.ad` or `ad test flows/` (runs all `.ad` files
in a directory).

## Native assets

The package bundles two native helpers that are managed automatically:

**Android snapshot helper** (13 KB APK) — provides multi-window
accessibility snapshots via `adb shell am instrument`. Captures system
UI (status bar, keyboard) alongside the app, unlike stock `uiautomator
dump`. Auto-installed on the device on first snapshot.

**iOS XCUITest runner** (~200 KB source) — Swift project built via
`xcodebuild build-for-testing` on first use. Provides snapshot, tap,
swipe, type, record, and other interactions through an HTTP bridge to
the simulator/device. Build output is cached in `ios-runner/build/`.

Both are resolved automatically — no manual build steps required.

## Environment variables

| Variable                              | Purpose                                                    |
| ------------------------------------- | ---------------------------------------------------------- |
| `AGENT_DEVICE_STATE_DIR`              | Override state directory (default: `~/.agent-device/`)     |
| `AGENT_DEVICE_VERBOSE`                | Set to `1` for diagnostic logging                          |
| `AGENT_DEVICE_ANDROID_SNAPSHOT_DEBUG` | Set to `1` for Android snapshot diagnostics                |
| `AGENT_DEVICE_IOS_RUNNER_DEBUG`       | Set to `1` for iOS runner HTTP diagnostics                 |
| `AGENT_DEVICE_IOS_RUNNER_BUILD_DIR`   | Override iOS runner build products path                    |
| `AD_RECORD_TESTS`                     | Set to a directory path to enable video recording in tests |

## License

MIT
