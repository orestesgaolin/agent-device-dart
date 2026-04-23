---
name: Phase 4 verification findings
description: Bugs, gaps, and patterns found during audit of commit 0df6bbc (Phase 4 AgentDevice runtime façade)
type: project
---

**Commit audited:** 0df6bbc (Phase 4 — AgentDevice + MemorySessionStore + contract types)

## Critical: copyWith cannot clear optional fields (null ≠ absent)

`CommandSessionRecord.copyWith` uses `appId: appId ?? this.appId` for every nullable field.
This means `_updateSession(appId: null)` silently preserves the old `appId` rather than clearing it.
The `closeApp` method calls `_updateSession(appId: null)` hoping to clear the app from session,
but it cannot. A test comment in `agent_device_test.dart:184` explicitly acknowledges this:
"actually copyWith keeps existing value for nulls, so we only assert the call shape."

This is a semantic gap: after `closeApp()`, the session still remembers the old appId.
Phase 5 will need this cleared so subsequent commands do not inherit a stale appId.

Fix: Use a sentinel/wrapper (e.g. `Optional<T>`) or add a separate `clearFields` list param
to distinguish "not passed" from "explicitly null". Same fix needed for all nullable fields
(appId, appBundleId, appName, snapshot, backendSessionId).

## Minor: maxImagePixels values differ from TS source

TS runtime.ts: both `localCommandPolicy` and `restrictedCommandPolicy` use `maxImagePixels: 20_000_000`.
Dart contract.dart: `localCommandPolicy` uses `50_000_000`, `restrictedCommandPolicy` uses `25_000_000`.
These are intentional Dart-port decisions (plan doesn't document them as deviations). The values
don't break anything now but will diverge from TS behavior when `capture-diff-screenshot` is ported.

## Minor: SnapshotState not exported from public barrel

`CommandSessionRecord.snapshot` is typed `SnapshotState?`. `SnapshotState` is NOT in the `show` list
of `lib/agent_device.dart` (only `SnapshotNode`, `SnapshotVisibility`, etc. are exported from snapshot.dart).
SDK consumers who read `record.snapshot` get a `SnapshotState?` they can't reference by name in their
own code without a separate import from the internal path.

Fix: Add `SnapshotState` to the snapshot.dart export line in `lib/agent_device.dart`.

## Minor: getClipboard has a no-op sessions.get chained before _ctx()

```dart
Future<String> getClipboard() => sessions
    .get(sessionName)
    .then((_) async => backend.getClipboard(await _ctx()));
```
The `sessions.get` result is discarded (`_`). This works but is misleading — it looks like
a guard but isn't. All other methods just call `backend.xxx(await _ctx())` directly.
No functional impact (backend.getClipboard still gets the right ctx via _ctx()), just noise.

## Missing from AgentDevice vs Backend coverage

These Backend methods have no AgentDevice wrapper. Most are in scope for Phase 5 or later, but
Phase 5 CLI will need some of them immediately:

Phase 5 blockers:
- `readText` — needed for `get` command
- `findText` — needed for `find` command
- `pinch` — needed for `pinch` command
- `pressKey` — needed for `press` command (keyboard keys)
- `handleAlert` — needed for `alert` command
- `pushFile` — needed for `push` command

Phase 6/later:
- `startRecording` / `stopRecording` — record command
- `startTrace` / `stopTrace` — trace command
- `readLogs` — logs command
- `dumpNetwork` — network command
- `measurePerf` — perf command
- `openSettings` — settings command
- `ensureSimulator` — iOS boot
- `resolveInstallSource` — install pipeline

## ArtifactAdapter and AbortSignal not in Dart AgentDevice

TS `AgentDeviceRuntime` has `artifacts: ArtifactAdapter` and `signal?: AbortSignal`.
Dart `AgentDevice` has neither. `ArtifactAdapter` is used by screenshot-diff commands (Phase 10+).
`AbortSignal` would map to Dart's `CancelToken`. Neither is a Phase 4 gap but Phase 5 CLI
needs at minimum a CancelToken/signal for timeout wiring.

## assertBackendCapabilityAllowed not ported

TS `runtime.ts` exports `assertBackendCapabilityAllowed(runtime, capability)`.
Dart has no equivalent. The `policy.allowNamedBackendCapabilities` field exists on `CommandPolicy`
but `AgentDevice` methods never check it before dispatching. Intentionally deferred (none of the
wired methods require escape-hatch capabilities), but must be added before Phase 5 if any CLI
commands use capability-gated backend methods.

## Session cloning not implemented in MemorySessionStore

TS `createMemorySessionStore` uses `cloneSessionRecord(record)` — a deep clone via `structuredClone`
for every `get` and `set`. Dart `MemorySessionStore` returns live references; mutation of a record
after `set` would be reflected on the next `get` without a store update. For Phase 4
(single-threaded, sessions never directly mutated by callers) this is safe in practice.
Will matter for Phase 6 daemon where concurrent access could be an issue.

## Non-findings (confirmed acceptable)

- `SnapshotState` in `CommandSessionRecord.snapshot`: correctly typed (internal use only in Phase 4).
- `screenshot` builds ctx inline (`BackendCommandContext(session: sessionName, deviceSerial: device.id)`)
  instead of calling `_ctx()`. This is intentional — screenshot doesn't need `appId`/`appBundleId`
  from session (confirmed: `captureScreenshot` Backend API only needs device serial and output path).
- `DeviceSelector.platform` is passed as `BackendDeviceFilter` pre-filter AND `_matches` post-filter.
  No double-filtering issue — `_toBackendPlatform` reduces to concrete platforms before passing to backend.
- `PlatformSelector.apple` maps to `AgentDeviceBackendPlatform.ios` in `_toBackendPlatform`. Documented
  in the method comment. Correct for device resolution (no "apple" platform in backend layer).
- `_toBackendPlatform` is file-private and not exported. Correct.
- `_FakeBackend` from tests is not exported. Correct.
- `BackendActionResult` is a typedef for `Object?`, so `AgentDevice.scroll` returning `Future<Object?>`
  is type-compatible with `Backend.scroll` returning `Future<BackendActionResult>`.
- All 13 required public symbols (AgentDevice, DeviceSelector, CommandSessionRecord, CommandSessionStore,
  MemorySessionStore, createMemorySessionStore, CommandPolicy, localCommandPolicy, restrictedCommandPolicy,
  CommandClock, SystemClock, DiagnosticsSink) are exported from the barrel.
- `CommandContext` (TS type with session/requestId/signal/metadata) is NOT ported. Its role is subsumed
  by `BackendCommandContext` which already carries `session`, `deviceSerial`, `appId`, `appBundleId`.
  Acceptable deviation — `CommandContext` was a pass-through container in TS, not an SDK surface.

**Why:** Auditing Phase 4 found one semantic bug (copyWith cannot clear fields), one missing barrel export
(SnapshotState), and a getClipboard style issue. Also catalogued Backend method gaps for Phase 5 planning.
**How to apply:** Before Phase 5 CLI work: fix copyWith null-clearing, add SnapshotState export, add
readText/findText/pressKey/handleAlert/pushFile wrappers to AgentDevice.
