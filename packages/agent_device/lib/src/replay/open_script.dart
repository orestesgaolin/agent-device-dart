/// Port of `agent-device/src/daemon/session-open-script.ts`.
/// Open action script helpers.
library;

import 'script_utils.dart';
import 'session_action.dart';

/// Append open action script args to [parts] based on [action].
void appendOpenActionScriptArgs(List<String> parts, SessionAction action) {
  for (final positional in action.positionals) {
    parts.add(formatScriptArg(positional));
  }
  if (action.flags['relaunch'] == true) {
    parts.add('--relaunch');
  }
  appendRuntimeHintFlags(parts, action.runtime?.toJson());
}

/// Parse open action flags from [args].
/// Returns a tuple of (positionals, flags, runtime).
({
  List<String> positionals,
  Map<String, Object?> flags,
  SessionRuntimeHints? runtime,
})
parseReplayOpenFlags(List<String> args) {
  final argsWithoutRelaunch = <String>[];
  final flags = <String, Object?>{};
  for (final token in args) {
    if (token == '--relaunch') {
      flags['relaunch'] = true;
      continue;
    }
    argsWithoutRelaunch.add(token);
  }
  final parsedRuntime = parseReplayRuntimeFlags(argsWithoutRelaunch);
  final runtimeHints = _hasReplayOpenRuntimeHints(parsedRuntime.flags)
      ? _mapToSessionRuntimeHints(parsedRuntime.flags)
      : null;
  return (
    positionals: parsedRuntime.positionals,
    flags: flags,
    runtime: runtimeHints,
  );
}

/// True if the runtime flags contain any hints.
bool _hasReplayOpenRuntimeHints(Map<String, Object?> flags) {
  return flags['platform'] != null ||
      flags['metroHost'] != null ||
      flags['metroPort'] != null ||
      flags['bundleUrl'] != null ||
      flags['launchUrl'] != null;
}

/// Convert a flags map to SessionRuntimeHints.
SessionRuntimeHints _mapToSessionRuntimeHints(Map<String, Object?> flags) {
  return SessionRuntimeHints(
    platform: flags['platform'] as String?,
    metroHost: flags['metroHost'] as String?,
    metroPort: flags['metroPort'] as int?,
    bundleUrl: flags['bundleUrl'] as String?,
    launchUrl: flags['launchUrl'] as String?,
  );
}
