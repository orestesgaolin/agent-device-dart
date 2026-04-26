// Port of agent-device/src/daemon/handlers/session-replay-vars.ts.
//
// `.ad` script parametrisation: ${VAR} substitution with ${VAR:-default}
// fallback and \${...} escape, sourced from (high → low precedence)
// CLI -e overrides, AD_VAR_* shell env, file `env KEY=VAL` directives,
// and trusted runtime built-ins (AD_PLATFORM / AD_SESSION / AD_FILENAME
// / AD_DEVICE / AD_ARTIFACTS).
//
// The AD_* namespace is reserved for built-ins — user/file/shell/CLI
// sources cannot define keys in that namespace, which closes the
// shadowing vector where e.g. `AD_VAR_AD_SESSION=evil` could override
// the trusted runtime value.
library;

import '../utils/errors.dart';
import 'session_action.dart';

/// Acceptable shape of a replay variable identifier — uppercase
/// letters / digits / underscores, starting with a letter or
/// underscore. Mirrors TS `REPLAY_VAR_KEY_RE`.
final RegExp replayVarKeyRe = RegExp(r'^[A-Z_][A-Z0-9_]*$');

const String _shellPrefix = 'AD_VAR_';
const String _reservedNamespacePrefix = 'AD_';

// Matches either an escape (`\${`) or an interpolation `${KEY}` /
// `${KEY:-default}`. Group 1: escape literal; group 2: key; group 3:
// raw default.
final RegExp _interpolationRe = RegExp(
  r'(\\\$\{)|\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-((?:[^}\\]|\\.)*))?\}',
);

/// Resolved variable scope after merging all sources. Use
/// [buildReplayVarScope] to construct.
class ReplayVarScope {
  final Map<String, String> values;
  ReplayVarScope(Map<String, String> values)
    : values = Map.unmodifiable(values);
}

/// Layered sources for [buildReplayVarScope]. Untrusted layers
/// (`fileEnv`, `shellEnv`, `cliEnv`) are walked in order of increasing
/// precedence so later layers override earlier ones; the trusted
/// `builtins` layer is seeded first and may legitimately use the AD_*
/// namespace.
class ReplayVarSources {
  final Map<String, String>? builtins;
  final Map<String, String>? fileEnv;
  final Map<String, String>? shellEnv;
  final Map<String, String>? cliEnv;

  const ReplayVarSources({
    this.builtins,
    this.fileEnv,
    this.shellEnv,
    this.cliEnv,
  });
}

bool _isReservedNamespaceKey(String key) =>
    key.startsWith(_reservedNamespacePrefix);

AppError _reservedNamespaceError(String key) => AppError(
  AppErrorCodes.invalidArgs,
  'The AD_* namespace is reserved for built-in variables. Rename $key '
  'to avoid the AD_ prefix.',
);

/// Merge the four layers of sources into a single scope. Throws if any
/// untrusted layer tries to define an AD_* key.
ReplayVarScope buildReplayVarScope(ReplayVarSources sources) {
  final merged = <String, String>{};
  // builtins are trusted (set by the runtime) and may use AD_*.
  final builtins = sources.builtins;
  if (builtins != null) {
    builtins.forEach((k, v) => merged[k] = v);
  }
  for (final layer in <Map<String, String>?>[
    sources.fileEnv,
    sources.shellEnv,
    sources.cliEnv,
  ]) {
    if (layer == null) continue;
    layer.forEach((k, v) {
      if (_isReservedNamespaceKey(k)) {
        throw _reservedNamespaceError(k);
      }
      merged[k] = v;
    });
  }
  return ReplayVarScope(merged);
}

/// Filter [processEnv] to entries with the `AD_VAR_` prefix and strip
/// the prefix. Stripped keys that would land back in the reserved AD_*
/// namespace (e.g. `AD_VAR_AD_SESSION`) are silently dropped.
Map<String, String> collectReplayShellEnv(Map<String, String> processEnv) {
  final result = <String, String>{};
  processEnv.forEach((rawKey, value) {
    if (!rawKey.startsWith(_shellPrefix)) return;
    final key = rawKey.substring(_shellPrefix.length);
    if (key.isEmpty) return;
    if (!replayVarKeyRe.hasMatch(key)) return;
    if (_isReservedNamespaceKey(key)) return;
    result[key] = value;
  });
  return result;
}

/// Parse `KEY=VALUE` strings (typically from a `-e` CLI flag) into a
/// flat map. Throws on malformed entries, invalid keys, or AD_*
/// namespace usage.
Map<String, String> parseReplayCliEnvEntries(List<String> entries) {
  final result = <String, String>{};
  for (final entry in entries) {
    final eqIndex = entry.indexOf('=');
    if (eqIndex <= 0) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid -e entry "$entry": expected KEY=VALUE.',
      );
    }
    final key = entry.substring(0, eqIndex);
    if (!replayVarKeyRe.hasMatch(key)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid -e key "$key": keys must be uppercase letters, digits, '
        'and underscores (e.g. APP_ID).',
      );
    }
    if (_isReservedNamespaceKey(key)) {
      throw _reservedNamespaceError(key);
    }
    result[key] = entry.substring(eqIndex + 1);
  }
  return result;
}

/// Substitute all `${VAR}` / `${VAR:-default}` references in [raw]
/// against [scope]. `\${` produces a literal `${`. Unresolved
/// references without a fallback throw an [AppError] tagged with
/// [file]:[line].
String resolveReplayString(
  String raw,
  ReplayVarScope scope, {
  required String file,
  required int line,
}) {
  return raw.replaceAllMapped(_interpolationRe, (match) {
    final escapedLiteral = match.group(1);
    if (escapedLiteral != null) return r'${';
    final key = match.group(2);
    if (key == null) return match.group(0)!;
    if (scope.values.containsKey(key)) return scope.values[key]!;
    final fallback = match.group(3);
    if (fallback != null) {
      // Unescape `\X` → `X` inside the fallback so users can write
      // closing braces / backslashes literally.
      return fallback.replaceAllMapped(
        RegExp(r'\\(.)'),
        (m) => m.group(1) ?? '',
      );
    }
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Unresolved variable \${$key} at $file:$line.',
    );
  });
}

/// Resolve all string fields on [action] (positionals, flag values,
/// runtime hints) against [scope].
SessionAction resolveReplayAction(
  SessionAction action,
  ReplayVarScope scope, {
  required String file,
  required int line,
}) {
  String resolve(String s) =>
      resolveReplayString(s, scope, file: file, line: line);
  final positionals = action.positionals.map(resolve).toList(growable: false);
  final flags = <String, Object?>{};
  action.flags.forEach((k, v) {
    flags[k] = v is String ? resolve(v) : v;
  });
  final runtime = action.runtime;
  final resolvedRuntime = runtime?.copyWith(
    platform: runtime.platform == null ? null : resolve(runtime.platform!),
    metroHost: runtime.metroHost == null ? null : resolve(runtime.metroHost!),
    bundleUrl: runtime.bundleUrl == null ? null : resolve(runtime.bundleUrl!),
    launchUrl: runtime.launchUrl == null ? null : resolve(runtime.launchUrl!),
  );
  return action.copyWith(
    positionals: positionals,
    flags: flags,
    runtime: resolvedRuntime,
  );
}

/// True if any of [actions] still carries a `${...}` interpolation
/// token after parsing — used to guard `replay -u` against rewriting
/// scripts whose substitutions would be silently dropped.
bool actionsContainInterpolation(List<SessionAction> actions) {
  bool containsToken(Object? value) => value is String && value.contains(r'${');
  for (final action in actions) {
    if (action.positionals.any(containsToken)) return true;
    if (action.flags.values.any(containsToken)) return true;
    final runtime = action.runtime;
    if (runtime != null) {
      if (containsToken(runtime.platform) ||
          containsToken(runtime.metroHost) ||
          containsToken(runtime.bundleUrl) ||
          containsToken(runtime.launchUrl)) {
        return true;
      }
    }
  }
  return false;
}
