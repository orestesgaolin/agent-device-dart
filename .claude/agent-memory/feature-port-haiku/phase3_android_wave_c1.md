---
name: Phase 3 Android Wave C1 Port Summary
description: Shared helpers + light Android platform files (permissions, appearance, scroll, device rotation, notifications, perf, input state)
type: project
---

## Summary

**Phase 3 Android Wave C1** successfully ported from TypeScript to Dart.

Date: 2026-04-23
Files: 10 source + 7 test files
Tests: 62 new tests (455 passing cumulative with all prior waves)
Status: Complete, analyzer clean, all tests pass

## Files Ported

### Shared Platform Helpers (lib/src/platforms/)

1. **appearance.dart** (28 LOC)
   - `AppearanceAction` enum: light, dark, toggle
   - `fromString()` parser with case-insensitive matching
   - Error handling for invalid states

2. **perf_utils.dart** (6 LOC)
   - `roundPercent()` - rounds double to nearest tenth for CPU/memory metrics

3. **permission_utils.dart** (97 LOC)
   - `PermissionAction` enum: grant, deny, reset
   - `PermissionTarget` enum: 13 mobile permission types
   - `allTargets` static list for validation
   - `fromString()` parsers with full enum coverage
   - Error messages for invalid targets

### Core Gesture & Rotation Helpers (lib/src/core/)

4. **device_rotation.dart** (39 LOC)
   - `DeviceRotation` enum: portrait, portrait-upside-down, landscape-left, landscape-right
   - Alias parsing: "upside-down" → portraitUpsideDown, "left" → landscapeLeft, etc.
   - Case-insensitive, trim-safe parsing

5. **open_target.dart** (40 LOC)
   - `isDeepLinkTarget()` - validates URI scheme format
   - `isWebUrl()` - detects HTTP/HTTPS URLs
   - `resolveIosDeviceDeepLinkBundleId()` - resolves Safari for web, fallback to app bundle
   - Scheme detection: http/https/ws/wss/ftp/ftps require `//`

6. **scroll_gesture.dart** (174 LOC)
   - `ScrollDirection` enum: up, down, left, right
   - `ScrollGestureOptions` - input parameters (direction, amount, pixels, reference dimensions)
   - `ScrollGesturePlan` - calculated coordinates (x1, y1, x2, y2) and pixel travel distance
   - `buildScrollGesturePlan()` - geometry calculation with clamping
   - Edge padding: 5% of axis length (minimum 1px)
   - Travel distance: clamped between 1px and (axis - 2*padding)
   - Half-travel centering for start/end coordinates
   - `parseScrollDirection()` - validation with error handling

### Android Platform Specific (lib/src/platforms/android/)

7. **open_target.dart** (62 LOC)
   - `AndroidAppTargetKind` enum: package, binary, other
   - `classifyAndroidAppTarget()` - heuristics for app target classification
   - Package name pattern: `^[A-Za-z_][\w]*(\.[A-Za-z_][\w]*)+$`
   - Binary detection: .apk/.aab extensions + path markers (/,\,.,~)
   - `looksLikeAndroidPackageName()` public validator
   - Error message helper for installer requirements

8. **notifications.dart** (79 LOC)
   - `AndroidBroadcastPayload` - action, receiver, extras (Map<String, Object?>)
   - `AndroidNotificationResult` - action, extrasCount
   - `pushAndroidNotification()` - sends adb broadcast with optional receiver + extras
   - Extra type handling: string (--es), boolean (--ez), number (--ei/--ef)
   - Default action: `{packageName}.TEST_PUSH` if not provided
   - Receiver optional via `-n` flag
   - Validates extra types, rejects unsupported types

9. **perf.dart** (244 LOC)
   - CPU sampling: `sampleAndroidCpuPerf()` → `AndroidCpuPerfSample`
   - Memory sampling: `sampleAndroidMemoryPerf()` → `AndroidMemoryPerfSample`
   - CPU parser: regex extraction of process name + percentage per line
   - Supports colon-separated subprocesses (e.g., `com.app:subprocess`)
   - Percentage rounding: `roundPercent()` to nearest tenth
   - Memory parser: TOTAL PSS + optional TOTAL RSS extraction
   - Comma-stripping for large numbers (1,234,567 → 1234567)
   - Fallback: tries TOTAL PSS label first, then TOTAL row parsing
   - Error handling: process not found detection, enriched details with hints
   - Timeout: 15 seconds for both CPU and memory samples

10. **device_input_state.dart** (292 LOC)
    - Keyboard state: `AndroidKeyboardState` (visible, inputType, type)
    - Keyboard type: 7 types (text, number, email, phone, password, datetime, unknown)
    - Visibility detection: mInputShown, mIsInputViewShown, isInputViewShown
    - InputType classification via bitmask:
      - Input class (bits 0-3): TEXT, NUMBER, PHONE, DATETIME
      - Variation (bits 4-11): EMAIL, PASSWORD variants, VISIBLE_PASSWORD
    - `getAndroidKeyboardState()` - queries dumpsys input_method
    - `dismissAndroidKeyboard()` - retries up to 2x with 120ms delay between attempts
    - Clipboard read/write: `readAndroidClipboardText()` / `writeAndroidClipboardText()`
    - Clipboard error handling: detects unsupported devices, normalizes text output
    - Prefix parsing: "clipboard text:" → extract value
    - Null normalization: "null" string → empty string

## Test Files

- **device_rotation_test.dart** (80 LOC, 7 tests)
  - Parsing: portrait, landscape-left/right aliases, upside-down alias
  - Case-insensitivity and whitespace trimming
  - Error cases: null, invalid rotation names
  - toString() round-trip

- **open_target_test.dart** (79 LOC, 9 tests)
  - isDeepLinkTarget: valid/invalid schemes, spacing, empty input
  - Scheme format validation: requires letter start
  - isWebUrl: HTTP/HTTPS detection only
  - resolveIosDeviceDeepLinkBundleId: fallbacks, whitespace handling

- **scroll_gesture_test.dart** (158 LOC, 11 tests)
  - buildScrollGesturePlan: direction-specific coordinate calculations
  - Custom pixel/amount overrides
  - Clamping to max travel distance
  - Validation: negative amounts/pixels rejected
  - parseScrollDirection: invalid direction error

- **permission_utils_test.dart** (110 LOC, 10 tests)
  - PermissionAction: all 3 actions, case-insensitive parsing, errors
  - PermissionTarget: all 13 targets, case-insensitive, null/invalid errors
  - allTargets list validation: 13 targets present

- **notifications_test.dart** (50 LOC, 4 tests)
  - AndroidBroadcastPayload construction
  - AndroidNotificationResult creation
  - Payload composition with various field combinations

- **perf_test.dart** (147 LOC, 10 tests)
  - parseAndroidCpuInfoSample: aggregation, rounding, filtering
  - parseAndroidMemInfoSample: PSS/RSS parsing, comma handling
  - Error cases: process not found, missing data
  - Sample type construction

- **device_input_state_test.dart** (104 LOC, 11 tests)
  - AndroidKeyboardType: all 7 types, toString()
  - AndroidKeyboardState/DismissResult construction
  - Keyboard type classification (text, email, phone, number, datetime, password)
  - Clipboard text normalization

## Key Design Decisions

### API Simplification (vs TS)
- Functions use `String serial` instead of `DeviceInfo` object
- Follows Wave A pattern: adbArgs(serial, args) not adbArgs(device, args)
- Decouples from BackendDeviceInfo which is Wave C3 (AndroidBackend assembly)

### Enum Pattern
- All closed-union types → enums with:
  - `value` getter for string representation
  - `fromString()` static factory (parser)
  - `toString()` override
- Permissions: all 13 Android permission types as enum variants

### Input Validation
- All parsers: `trim().toLowerCase()` for case-insensitive, whitespace-safe matching
- Clear error messages: show valid options in AppError details
- Null-safe: proper handling of optional values (null coalescing `??`)

### Bitmask Classification (Keyboard Types)
- Android InputType constants as const integers
- `parsed & MASK` for bitfield extraction
- Sequential if-else for input class classification (NUMBER, PHONE, DATETIME, TEXT)
- Nested classification for TEXT variations (EMAIL, PASSWORD, VISIBLE_PASSWORD)

### Regex Robustness (CPU/Memory Parsing)
- CPU regex expects trailing space: `/^%\s+\d+\/([^\s]+):\s/`
- Double parsing with trim-strip-parse fallback for numbers with commas
- RegExp.escape() for label matching (handles special chars)
- Case-insensitive matching for visibility keys

### Error Handling
- Detailed error context: metric, package, hint suggestions
- Error annotation: wraps native exceptions in AppError with added metadata
- Transient detection: recognizes retryable ADB errors (not yet in Wave C1)

## Dependencies

**Already ported (imported directly)**:
- `package:agent_device/src/utils/errors.dart` - AppError, AppErrorCodes
- `package:agent_device/src/utils/exec.dart` - runCmd, ExecOptions
- `package:agent_device/src/utils/timeouts.dart` - sleep
- `package:agent_device/src/platforms/android/adb.dart` - adbArgs, ensureAdb, isClipboardShellUnsupported
- Dart stdlib: `dart:io`, `dart:async`, `dart:convert`

**Not ported (Wave C2/C3)**:
- presentation-based hints
- device isolation filtering
- boot diagnostics

## Code Quality

- **Strict analyzer**: 0 errors, 0 warnings, only info-level lints
- **Format compliance**: Applied via `dart format`
- **Documentation**: Comprehensive doc comments on all public functions
- **Null safety**: Proper use of `?` and `??` operators
- **Constants**: All magic numbers as named const (e.g., `_androidKeyboardDismissMaxAttempts`)

## Test Count Summary

- Device Rotation: 7 tests
- Open Target: 9 tests
- Scroll Gesture: 11 tests
- Permission Utils: 10 tests
- Notifications: 4 tests
- Perf: 10 tests
- Device Input State: 11 tests
- **Total Wave C1: 62 tests** (+62 cumulative: 393 → 455)

## Integration Points for Wave C2/C3

1. **AndroidBackend class** will wire these functions into backend interface methods
2. **Scroll gesture** will be called from backend.scroll() with direction + options
3. **Device rotation** will be called from backend.rotate()
4. **Keyboard dismiss** will be called before input operations to clear IME
5. **Clipboard read/write** will be exposed via backend.readText() / backend.fillText()
6. **Notifications** will be called from backend.notify()
7. **Perf sampling** will be called from backend.measurePerf()

---

## Notable Discoveries

- TS adbArgs() takes DeviceInfo, but Dart wave A simplified to String serial
- CPU regex requires trailing space after colon (`:` must be followed by `\s`)
- Keyboard type classification needs nested if-else for input variations
- Appearance/Perf-Utils are trivial but needed for completeness in the export surface
- HTTP/HTTPS special case: require `//` after scheme (other schemes don't)
