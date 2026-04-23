---
name: Phase 3 verification findings
description: Bugs, gaps, and patterns found during audit of commits 1c035f4..73299f0 (Phase 3 backend + Android)
type: project
---

**Commits audited:** 1c035f4..73299f0 (7 commits: backend interface + Android Wave A/B/C1/C2/C3)

## Missed Backend wirings (AndroidBackend doesn't wire TS-supported functions)

These Backend methods are NOT wired in AndroidBackend but the TS Android platform DOES support them via android/index.ts exports. Phase 4 runtime will silently fall over on these.

1. **scroll** — `scrollAndroid` is ported and works; `parseScrollDirection(options.direction)` exists. Fix: add override with `parseScrollDirection(options.direction)` call, coerce `int?` to `double?`.
2. **setKeyboard** — `getAndroidKeyboardState` + `dismissAndroidKeyboard` are ported. TS `system.ts` command layer calls `backend.setKeyboard` (confirmed). Fix: implement using action-based dispatch.
3. **listApps** — `listAndroidApps` is ported. TS `commands/apps.ts` calls `backend.listApps`. Fix: delegate to `listAndroidApps(_serial(ctx), filter)`.
4. **triggerAppEvent** — `pushAndroidNotification` is ported. TS `commands/apps.ts` calls `backend.triggerAppEvent`. Fix: map event to notification payload and call `pushAndroidNotification`.
5. **bootDevice** — `openAndroidDevice` is ported. TS `commands/admin.ts` calls `backend.bootDevice`. Fix: call `openAndroidDevice(_serial(ctx))`.
6. **installApp** — `installAndroidApp` is ported (but `.aab` bundletool path stubs out). TS session-deploy calls it directly, NOT via `backend.installApp`. Lower priority, but wiring needed for Phase 4 uniformity.
7. **reinstallApp** — `reinstallAndroidApp` is ported. Same call pattern as installApp.

Scroll is documented in plan as a known gap with fix recommendation. Others are undocumented gaps.

## Logic drop: device.target TV/mobile branching (app_lifecycle.dart line 159)

TS `resolveAndroidLaunchCategories(device)` branches on `device.target === 'tv'` vs `'mobile'`.
Dart `_resolveAndroidLaunchCategories(deviceId)` has a `TODO(port): Fetch device target from device info` comment and always uses LAUNCHER (mobile) unless `includeFallback` is true (in which case it returns both).

Impact: opening apps on Android TV emulators may use wrong launcher category (LAUNCHER instead of LEANBACK_LAUNCHER). This is pre-documented as a TODO in the code.

## Logic drop: device.booted conditional in openAndroidApp

TS: `if (!device.booted) { await waitForAndroidBoot(device.id); }`
Dart: `await waitForAndroidBoot(deviceId);` — unconditional.

Net effect: Dart always waits for boot signal even when device is already booted. This is a minor perf regression (extra adb round trip) but not a correctness bug.

## Logic drop: emulator fingerprint attempt in settings.dart

TS `_androidFingerprintCommandAttempts` adds `['emu', 'finger', 'touch', fingerprintId]` when `device.kind === 'emulator'`.
Dart `_androidFingerprintCommandAttempts` only has the two `shell cmd fingerprint` attempts; emulator telnet path is dropped.

Impact: fingerprint simulation on Android emulators via `emu finger touch` is unavailable. Physical device path (`shell cmd fingerprint`) still works and is tried first. Low-priority gap.

## Incomplete integration test

`android_emulator_it_test.dart` gates correctly on `AGENT_DEVICE_ANDROID_IT=1` and skips cleanly without it. However, when enabled, the test body only checks `backend.platform == android`. All actual calls (`openApp`, `captureSnapshot`, etc.) are commented out as TODOs. The test provides no functional validation of wired methods.

## Test quality: passes-by-construction

`input_actions_test.dart`: Every test constructs an expected array inline and then asserts `expected.sublist(2)` equals a literal. The actual `pressAndroid()`, `swipeAndroid()` etc. functions are NEVER called. Tests validate hardcoded constants against themselves.

`settings_test.dart`: Regex patterns tested in isolation without calling `_parseAndroidAppearance()` or `setAndroidSetting()`.

`snapshot_test.dart`: Tests check `expect(dumpUiHierarchy, isA<Function>())` — pure function-existence checks.

`notifications_test.dart`: Tests instantiate DTOs and assert field values. Does not call `pushAndroidNotification()`.

These tests pass trivially and would not catch logic regressions in the functions they purport to cover.

## dynamic usage in lib/src/ (minor lint)

`snapshot.dart` lines 218, 235: `bool _isRetryableAdbError(dynamic err)` and `bool _isUiHierarchyDumpTimeout(dynamic err)`. These are private helpers called from a `withRetry` callback whose `shouldRetry` parameter is typed `bool Function(Object error, int attempt)`. Using `Object` instead of `dynamic` would be more precise and match the surrounding type contract.

`exec.dart` line 601: `String _decodeOutput(dynamic output)` — private; same concern.

`dart analyze` doesn't flag these; they don't violate any currently-enabled lint rule.

## Partial port: bundletool AAB installation

`_installAndroidAppBundle` (app_lifecycle.dart line 770) throws `UnimplementedError`. The TS source has full bundletool integration (detect binary, fall back to JAR via `AGENT_DEVICE_BUNDLETOOL_JAR`). AAB file installs will fail at runtime. Documented as a TODO in code.

## Wave C3 refactor correctness (93cf753 → 73299f0)

The 93cf753 skeleton had only 2 genuinely wired methods (captureSnapshot + captureScreenshot), both using `ctx.appId ?? ''` as the serial (wrong). The 73299f0 refactor correctly wired 18 methods using `_serial(ctx)` (which reads `ctx.deviceSerial`). No regression — the refactor expanded wiring from 2 to 18 and fixed the serial field.

## Non-findings (confirmed acceptable)

- `BackendCommandContext.deviceSerial`: Dart-port addition, expected.
- `pinch`, `pressKey`, `handleAlert`, `openSettings`, `pushFile`, `ensureSimulator`, `resolveInstallSource`, `startRecording`, `stopRecording`, `startTrace`, `stopTrace`, `readLogs`, `dumpNetwork`: TS Android has no corresponding implementation in android/index.ts → unsupported defaults are correct.
- `measurePerf`: `perf.dart` has `sampleAndroidCpuPerf`/`sampleAndroidMemoryPerf` but they are NOT exported from TS android/index.ts — not a Backend wire point.
- `openSettings`: TS backend has it but TS Android has no openSettings function; settings are managed via `setAndroidSetting`. Unsupported default is correct.

**Why:** Auditing Phase 3 found 7 missed Backend wirings (5 confirmed Phase 4 blockers, 2 lower-priority), 3 dropped logic paths, and systemic weak test quality on Wave C files.
**How to apply:** Reference when reviewing Phase 4 work; the 5 critical wirings (scroll, setKeyboard, listApps, triggerAppEvent, bootDevice) should be added before Phase 4 runtime dispatch is built on top of AndroidBackend.
