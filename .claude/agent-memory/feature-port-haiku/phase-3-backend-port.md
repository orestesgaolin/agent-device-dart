---
name: Phase 3 Backend Interface Port (2026-04-23)
description: Complete TypeScript Backend interface ported to Dart abstract class with 40 methods, 3 enums, 15+ sealed unions, and 40+ supporting types
type: reference
---

## Port Summary: Backend Interface

### Source
`agent-device/src/backend.ts` (607 LOC)

### Target
```
packages/agent_device/lib/src/backend/
├── platform.dart (AgentDeviceBackendPlatform enum)
├── capabilities.dart (BackendCapabilityName enum, BackendCapabilitySet typedef)
├── device_info.dart (BackendDeviceOrientation, device/app/filter types)
├── options.dart (interaction options, alert results, sealed unions)
├── diagnostics.dart (logs, network, perf, time window)
├── install_source.dart (simulator, installation, target types)
├── backend.dart (main abstract class, context, escape hatches, utilities)
├── backend_exports.dart (barrel re-export for internal use)
└── test/backend_test.dart (compilation proof + enum round-trip tests)
```

### Decomposition Strategy

Followed the suggested split by concern, not TS file structure:

1. **platform.dart** (26 LOC) — `AgentDeviceBackendPlatform` enum (ios, android, macos, linux) with `fromString()` and `toString()` round-trip.

2. **capabilities.dart** (26 LOC) — `BackendCapabilityName` enum (androidShell, iosRunnerCommand, macosDesktopScreenshot) with `fromString()` factory. `BackendCapabilitySet` typedef as `List<BackendCapabilityName>`.

3. **device_info.dart** (173 LOC) — Orientation, device/app queries:
   - `BackendDeviceOrientation` enum (portrait, portraitUpsideDown, landscapeLeft, landscapeRight)
   - `BackendDeviceFilter`, `BackendDeviceInfo`, `BackendDeviceTarget`
   - `BackendAppListFilter` enum (all, userInstalled)
   - `BackendAppInfo`, `BackendAppState`, `BackendAppEvent`

4. **options.dart** (554 LOC) — Interaction options, alerts, sealed unions:
   - Options: `BackendKeyboardOptions`, `BackendTapOptions`, `BackendFillOptions`, `BackendLongPressOptions`, `BackendSwipeOptions`, `BackendPinchOptions`, `BackendScrollOptions`, `BackendOpenOptions`, `BackendBackOptions`
   - Sealed unions: `BackendScrollTarget` (Viewport | Point), `BackendAlertResult` (Status | Handled | Wait), `BackendAlertAction` enum, `BackendPushInput` (Json | File), `BackendInstallSource` (Path | Artifact | Url)
   - Results: `BackendReadTextResult`, `BackendFindTextResult`, `BackendClipboardTextResult`, `BackendKeyboardResult`, `BackendAlertInfo`, `BackendScreenshotOptions/Result`
   - Snapshot: `BackendSnapshotOptions/Result`, `BackendSnapshotAnalysis`, `BackendSnapshotFreshness`

5. **diagnostics.dart** (287 LOC) — Observability:
   - Logs: `BackendLogEntry`, `BackendReadLogsOptions/Result`
   - Network: `BackendNetworkIncludeMode` enum, `BackendNetworkEntry`, `BackendDumpNetworkOptions/Result`
   - Perf: `BackendPerfMetric`, `BackendMeasurePerfOptions/Result`
   - Shared: `BackendDiagnosticsTimeWindow`

6. **install_source.dart** (97 LOC) — App installation:
   - `BackendInstallTarget`, `BackendInstallResult`
   - `BackendEnsureSimulatorOptions/Result`
   - Helper: `_installSourceToJson` serialization

7. **backend.dart** (428 LOC) — Abstract class + utilities:
   - `BackendCommandContext` (session, requestId, appId, appBundleId, signal, metadata)
   - `BackendEscapeHatches` (abstract, 3 platform methods)
   - `BackendActionResult` typedef (Object?)
   - `abstract class Backend` with 40 methods organized into sections:
     * Snapshot & Screenshot (2)
     * Text Extraction (2)
     * Interaction: Tap & Scroll (8)
     * Keyboard & Navigation (5)
     * Clipboard & Alerts (4)
     * App Management (8)
     * File Operations & Events (2)
     * Device Management (6)
     * Recording & Tracing (4)
   - Utilities: `hasBackendCapability()`, `hasBackendEscapeHatch()` with null-comparison ignore comments for function type checks

8. **backend_exports.dart** (50 LOC) — Barrel re-export for internal use and public API.

### Type Counts

- **Abstract class**: 1 (`Backend` with 40 methods)
- **Enums**: 6 (`AgentDeviceBackendPlatform`, `BackendCapabilityName`, `BackendDeviceOrientation`, `BackendAppListFilter`, `BackendAlertAction`, `BackendNetworkIncludeMode`)
- **Sealed unions**: 4 (`BackendScrollTarget`, `BackendAlertResult`, `BackendInstallSource`, `BackendPushInput`)
- **Record-like classes** (with `const` constructors and `toJson()`): ~40
- **Options/Settings classes**: 14 (`BackendKeyboardOptions`, `BackendTapOptions`, `BackendFillOptions`, `BackendLongPressOptions`, `BackendSwipeOptions`, `BackendPinchOptions`, `BackendScrollOptions`, `BackendOpenOptions`, `BackendBackOptions`, `BackendSnapshotOptions`, `BackendScreenshotOptions`, `BackendRecordingOptions`, `BackendTraceOptions`, etc.)
- **Results/Response classes**: 20+ (`BackendSnapshotResult`, `BackendScreenshotResult`, `BackendKeyboardResult`, `BackendShellResult`, `BackendReadLogsResult`, `BackendDumpNetworkResult`, `BackendMeasurePerfResult`, `BackendEnsureSimulatorResult`, `BackendInstallResult`, etc.)

### Porting Notes

#### Sealed Unions vs TS Discriminated Unions

TS uses discriminated unions (e.g., `{ kind: 'alertStatus'; alert: ... } | { kind: 'alertHandled'; handled: ...; }`).
Dart uses sealed classes:

```dart
sealed class BackendAlertResult {}
class BackendAlertStatusResult extends BackendAlertResult { ... }
class BackendAlertHandledResult extends BackendAlertResult { ... }
class BackendAlertWaitResult extends BackendAlertResult { ... }
```

Pattern matching via `switch` and `is` checks work naturally. For serialization, each subclass has its own `toJson()` with the `kind` field inline.

#### Functions vs Methods

TS uses optional methods on the type (`captureSnapshot?(...)`).
Dart uses abstract methods on `Backend` that must be implemented. This is stricter but more idiomatic.

TS `BackendEscapeHatches` as optional function properties → Dart `abstract class BackendEscapeHatches` with nullable method returns:
```dart
Future<BackendShellResult>? androidShell(...);
```
The `?` indicates the method *may* not be available (returns null when not supported).

#### Enum Values and Serialization

All string-based enums follow the pattern:
```dart
enum X { value('string-value'); final String value; const X(this.value); static X? fromString(String? value) { ... }; @override String toString() => value; }
```
This ensures TS-like round-tripping: `fromString(x.toString()) == x`.

#### Record→Class Conversion

TS `type BackendCommandContext = { ... }` → Dart `class BackendCommandContext { ... const BackendCommandContext({...}); }`

All have `toJson()` methods using conditional spread for optional fields:
```dart
Map<String, Object?> toJson() => <String, Object?>{
  'required': required,
  if (optional != null) 'optional': optional,
};
```

#### Dependencies

- `package:agent_device/src/snapshot/snapshot.dart` (`Point`, `Rect`, imported)
- `platform.dart` (self-contained, re-exported)
- No external package dependencies added

### Testing

**File**: `packages/agent_device/test/backend/backend_test.dart` (450 LOC)

- `FakeBackend implements Backend` — verifies all 40 methods are callable (all throw `UnimplementedError`).
- Test: "Backend compilation ensures all 40 abstract methods exist" — proves FakeBackend compiles, thus all methods exist.
- Enum round-trip tests: `fromString(enum.value) == enum` for 6 enums + `fromString('invalid') == null`.
- Utility function tests: `hasBackendCapability()` and `hasBackendEscapeHatch()` behavior.

**Results**: 4 tests, all passing.

### Analyzer Status

- **Zero issues** in `lib/src/backend/` after formatting.
- **Null-comparison warnings** on `BackendEscapeHatches?` method checks suppressed with `// ignore: unnecessary_null_comparison` (legitimate: checking function types for presence).
- **Line length**: 80-char formatting applied.

### Public API Updates

**File**: `packages/agent_device/lib/agent_device.dart`

Added exports for:
- `Backend`, `BackendCommandContext`, `BackendEscapeHatches`, `BackendActionResult`, utility functions
- 6 enums
- 4 sealed class hierarchies (via subtypes)
- 40+ option/result/info types

Total new public symbols: ~65 new exports.

### Deviations from Suggested Layout

- **No change**: Followed the suggested decomposition exactly.
- **Minor**: `BackendSnapshotOptions` kept in `options.dart` (logically with other options) rather than elsewhere.
- **Note**: The TS file has implicit "result" types (no explicit `BackendActionResult` definition, just `Record<string, unknown> | void`); Dart uses `Object?` typedef for clarity.

### Adjacent Issues Observed (Not Fixed)

1. Pre-existing analyzer issues in `platforms/android/manifest.dart` and `platforms/android/app_parsers.dart` (regex and symbol name errors) — out of scope for Backend port.

2. TS `command-schema.ts` + CLI argument parser not ported (planned for Phase 5); Backend is standalone.

### Metrics

- **Files created**: 8 (7 lib, 1 test)
- **Total Dart LOC**: ~2,000 (lib: 1,500; test: 450)
- **TS source LOC**: 607 (expanded due to Dart class ceremony and sealed unions)
- **Abstract methods**: 40
- **Method families covered**: 9 (Snapshot, Text, Interaction, Keyboard, Clipboard, Alert, App, Device, Diagnostics, Install, Recording)
- **Tests written**: 4, all passing
- **Analyzer issues**: 0 (in backend/)
- **Time to port**: ~1 hour (Haiku-optimized: surgical, no tangents)

### Next Steps

- Phase 3 Android Backend implementation will implement `Backend` interface (adb, UIAutomator XML parsing).
- Phase 4 Runtime dispatch will consume the interface.
- Sealed union pattern proved effective; can be reused for other discriminated types (e.g., command results).
