# `package:agent_device`

Dart port of the TypeScript [`agent-device`](https://github.com/roszkowski/agent-device-dart)
CLI and library. Drives mobile UI automation, snapshots, log/network/
perf observability, video recording, and `.ad` replay scripts against
iOS and Android devices.

Ships as both a CLI (`agent-device` / `ad`) and a Dart library you
can import into any Dart / Flutter project.

For the user-facing docs, feature matrix, setup, and the full porting
history see the [workspace README](../../README.md) and
[`PORTING_PLAN.md`](../../PORTING_PLAN.md) at the repo root. This file
exists so pub.dev (or any package consumer) sees a self-contained
intro.

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

`AgentDevice` is a typed façade over the abstract `Backend`. `IosBackend`
and `AndroidBackend` subclasses fill in what each platform supports;
everything else inherits an `UNSUPPORTED_OPERATION` default so partial
support is honest.

## CLI usage

```bash
# 1. Bootstrap the workspace.
make get

# 2. (iOS, one-time per target) Build the XCUITest runner.
xcodebuild build-for-testing \
  -project ios-runner/AgentDeviceRunner/AgentDeviceRunner.xcodeproj \
  -scheme AgentDeviceRunner \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath ios-runner/build

# 3. Drive a simulator.
xcrun simctl boot "iPhone 17"
dart run packages/agent_device/bin/agent_device.dart \
  devices --platform ios --json

# Or compile a static binary:
make compile      # produces dist/agent-device + dist/ad
./dist/agent-device --help
```

Every command takes `--platform ios|android`, `--serial <udid|id>`,
`--session <name>`, and emits either human-readable text or `--json`.
Session state persists across invocations under `~/.agent-device/sessions/`.

## License

See the [`LICENSE`](../../LICENSE) file at the workspace root.
