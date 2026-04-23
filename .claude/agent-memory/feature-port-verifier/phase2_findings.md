---
name: Phase 2 verification findings
description: Bugs and gaps found during audit of commit e4c82b7 (Phase 2 utils port)
type: project
---

**Commit audited:** e4c82b7 (feat(utils): phase 2 port — exec, png, diagnostics, retry, path, timeouts)

## Critical bugs

### Bug 1: Null-byte check corrupted (exec.dart lines 417, 426)
TS source checks `candidate.includes('\0')` (ASCII NUL, char code 0).
Dart port checks `candidate.contains('0')` (digit zero, char code 48).
- **Security gap:** NUL bytes in command/path strings are NOT rejected.
- **Correctness bug:** Any command or path containing the digit `'0'` is wrongly rejected with `INVALID_ARGS`.
- No current TS call site passes a command with `'0'` in the name, so tests pass, but this will silently break future callers.
- Fix: change `contains('0')` to `contains('\x00')` at both locations.

### Bug 2: Timeout kill signal SIGTERM vs SIGKILL (exec.dart line 312)
TS: `child.kill('SIGKILL')` — forcibly kills the process.
Dart: `process.kill(ProcessSignal.sigterm)` — sends a graceful shutdown signal.
A process that traps SIGTERM will ignore it and never exit, causing the `runCmd` future to never complete.
Fix: use `ProcessSignal.sigkill` instead.

## Minor issues

### sleep() signature breaking change (timeouts.dart)
TS: `sleep(ms: number): Promise<void>` — takes milliseconds as int.
Dart: `sleep(Duration duration): Future<void>` — takes a Duration object.
Future callers porting from TS must wrap `ms` in `Duration(milliseconds: ms)`.
The barrel exports this; will be a visible API break.

### resolveTimeoutMs float parsing (timeouts.dart)
TS: `Number('1.5')` → 1.5 → floors to 1.
Dart: `int.tryParse('1.5')` → null → returns fallback.
Impact is low since env vars providing timeout values are almost always integers.

### flushDiagnosticsToSessionFile HOME fallback (diagnostics.dart line 298)
TS uses `os.homedir()` which is cross-platform.
Dart uses `Platform.environment['HOME'] ?? ''` which returns empty string on systems without HOME set.
A flush attempt without HOME set would try to create files under `/logs/...` relative paths.
Fix: use `Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? ''` or read from path_resolution.

### Missing test: CancelToken integration with retryWithPolicy
Tests verify CancelToken's `isAborted` property but do NOT verify the cancel-before-first-attempt behavior
(i.e., passing a pre-aborted CancelToken to retryWithPolicy should immediately throw).

### Missing test: Zone propagation through nested async tasks
diagnostics_test.dart exercises basic async propagation but does not test zone scope visibility
inside a `Future.microtask`, `Future.delayed`, or timer callback spawned from within the scope.

### ExecBackgroundResult / ExecDetachedOptions defined but not exported
These classes are defined in exec.dart but not exported in the barrel.
runCmdBackground and runCmdDetached have no implementation — only a TODO comment.
The iOS runner (runner-session.ts) and Android emulator (devices.ts) depend on these.

**Why:** Track bugs that need fixing before or during Phase 3.
**How to apply:** Reference when reviewing Phase 3 work that touches exec.dart or timeouts.dart.
