// Port of agent-device/src/platforms/ios/simctl.ts (trimmed for MVP).
//
// The TS source threads a `--set <simulatorSetPath>` flag for multi-tenant
// isolation; the Dart port's Phase 8A MVP targets the user's default
// simulator set, so the flag is omitted. Multi-tenant support lands with
// the device-isolation port later (Phase 11).
library;

/// Prefix [args] with `simctl`. `xcrun simctl …` is the full invocation.
List<String> buildSimctlArgs(List<String> args) => ['simctl', ...args];
