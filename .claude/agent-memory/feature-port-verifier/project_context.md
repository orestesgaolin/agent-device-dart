---
name: Project context
description: agent-device TS→Dart port project structure, phases, and conventions
type: project
---

TypeScript source lives at `agent-device/src/` (npm package, no build step needed).
Dart target lives at `packages/agent_device/lib/src/`.
Tests live at `packages/agent_device/test/`.

**Phase structure:**
- Phase 0: scaffold + errors + redaction
- Phase 1: selectors DSL + replay script + snapshot model
- Phase 2: exec, png, diagnostics, retry, path_resolution, timeouts (commit e4c82b7)
- Phase 3 (next): backend interface + Android backend

**Port conventions established:**
- First-line comment must be `// Port of agent-device/src/utils/<name>.ts` (single-slash // or triple ///)
- Public API barrel: `packages/agent_device/lib/agent_device.dart` with explicit `show` lists
- Types that don't exist in TS source are acceptable if they improve Dart ergonomics (e.g. EmitDiagnosticOptions)
- `AbortSignal` → `CancelToken` is the established adaptation pattern
- `AsyncLocalStorage` → `Zone.current` + `runZoned(zoneValues:)` is the established adaptation

**Test command:** `dart test packages/agent_device`
**Analyze command:** `dart analyze packages/agent_device`
**Format check:** `dart format --output=none --set-exit-if-changed packages/agent_device`

**Why:** Need full context to verify subsequent phases quickly.
**How to apply:** Use as orientation before starting any new verification session.
