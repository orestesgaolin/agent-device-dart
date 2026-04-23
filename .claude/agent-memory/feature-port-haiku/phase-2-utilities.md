---
name: Phase 2 Utilities Port Patterns
description: TS→Dart patterns for diagnostics, retry, path resolution, timeouts (ported 2026-04-23)
type: reference
---

## Port Decision: Version Handling
- **Decision**: Leave existing `lib/src/version.dart` (static) as-is. TS `version.ts` reads package.json at runtime, but this adds little value in Dart.
- **Why**: Dart ecosystem standardizes on static pubspec versions; runtime reads risk failures that static constants avoid.

## Node→Dart Equivalents Used

### AsyncLocalStorage → Zone + zoneValues
- Node's `AsyncLocalStorage<T>` becomes Dart `Zone.current[key]` with `runZoned(fn, zoneValues: {key: value})`.
- **Why**: Dart Zones propagate through async task chains natively; no ThreadLocal equivalent needed.
- **Pattern**: Define a constant `Symbol` key (`#diagnosticsScope`), store scope in zone, retrieve via `Zone.current[key] as Type?`.

### Crypto randomness
- Node's `crypto.randomBytes(8).toString('hex')` → Dart `Random.secure().nextInt(256)` in a loop, formatted as hex.
- **Why**: `dart:math` `Random.secure()` is the native equivalent; use `toRadixString(36)` for timestamps.
- **Pattern**: Generate hex as `hexChars[byte >> 4] + hexChars[byte & 0xf]`.

### Environment variables
- Node's `process.env` → `Platform.environment` (from `dart:io`).
- **Pattern**: `Platform.environment['HOME']` or `Platform.environment['USERPROFILE']` on Windows.

### File I/O
- Node's `fs.appendFile(path, data, callback)` → `File(path).writeAsStringSync(data, mode: FileMode.append)`.
- **Why**: Dart prefers synchronous methods in diagnostics to keep overhead minimal.

### Sleep with cancellation
- Node's `sleep(ms)` + `AbortSignal` → custom `CancelToken` class with `abort()` / `isAborted` + manual timer management.
- **Why**: Dart doesn't have native AbortSignal; encapsulate token + listener list.

### Error classification
- TS retry predicate receives `error` object; Dart receives `Object` (more general, handles any throw).
- **Pattern**: `shouldRetry: (error, attempt) => error is TimeoutException` (use `is` checks).

## Analyzer & Linter Fixes
- **Unused stack traces in catch**: Use `catch (_)` instead of `catch (e, st)` if stack trace unused.
- **Flow control braces**: Lint requires `if (cond) { break; }` not `if (cond) break;`.
- **Nullable comparison**: Use `(value?.prop) == true` instead of `value?.prop ?? false`.
- **Type arguments in generics**: Always explicit: `Future<void>.delayed()` not `Future.delayed()`.

## Test Patterns
- Avoid real timing delays in tests; use `Completer`, `nowMs` parameters in deadline tests.
- Exception matching: prefer `try/catch` + `expect(caught, true)` over `throwsException` for fine-grained control.
- Diagnostic scope testing: no way to inspect internal event list; verify via side effects (flush, meta retrieval).

## Files Ported (Phase 2)
1. `path_resolution.dart` (27 LOC) – home expansion, path resolution
2. `timeouts.dart` (19 LOC) – timeout parsing, sleep helper
3. `diagnostics.dart` (367 LOC) – scope management, event emission, session logging (Zone-based)
4. `retry.dart` (362 LOC) – exponential backoff, deadline, cancel tokens, telemetry

**Test count**: 55 tests, 100% passing. Analyze clean (lib). No analyzer issues in new utility files.

## Exports Added to `agent_device.dart`
All public types and functions re-exported. Hidden: internal `_DiagnosticsScope`, `_createDiagnosticId`, `_computeDelay`, `_sleep`, `_publishRetryEvent`.
