/// Port of `agent-device/src/daemon/handlers/session-replay-script.ts`.
/// Main replay script parser and serializer.
library;

import 'dart:convert';

import '../utils/errors.dart';
import 'open_script.dart';
import 'replay_vars.dart' show replayVarKeyRe;
import 'script_utils.dart';
import 'session_action.dart';

/// Platform selector for replay scripts (excludes 'apple').
typedef ReplayScriptPlatform = String; // 'ios', 'android', 'macos', or 'linux'

const _replayMetadataPlatforms = {'ios', 'android', 'macos', 'linux'};

/// Metadata extracted from the context header of a replay script.
class ReplayScriptMetadata {
  final ReplayScriptPlatform? platform;
  final int? timeoutMs;
  final int? retries;

  /// File-local `env KEY=VALUE` directives, in source order. Drives the
  /// fileEnv layer of replay variable resolution. Null when the script
  /// has no env directives (distinct from an empty map for round-trip
  /// fidelity).
  final Map<String, String>? env;

  const ReplayScriptMetadata({
    this.platform,
    this.timeoutMs,
    this.retries,
    this.env,
  });

  /// JSON serialization.
  Map<String, Object?> toJson() => {
    if (platform != null) 'platform': platform,
    if (timeoutMs != null) 'timeoutMs': timeoutMs,
    if (retries != null) 'retries': retries,
    if (env != null && env!.isNotEmpty) 'env': env,
  };

  @override
  String toString() =>
      'ReplayScriptMetadata(platform: $platform, timeoutMs: $timeoutMs, '
      'retries: $retries, env: $env)';
}

/// Result of [parseReplayScriptDetailed]: the action list plus the
/// 1-based line number each action lives on. Used by the replay
/// runtime to attach `file:line` to interpolation errors.
class ParsedReplayScript {
  final List<SessionAction> actions;
  final List<int> actionLines;
  const ParsedReplayScript({required this.actions, required this.actionLines});
}

/// Parse a replay script string into a list of [SessionAction]s.
/// Comments, blank lines, env directives, and context headers are
/// skipped. Throws on misplaced env directives (must precede actions).
List<SessionAction> parseReplayScript(String script) =>
    parseReplayScriptDetailed(script).actions;

/// Parse a replay script and also return the 1-based source line for
/// every action, so callers can produce file:line diagnostics during
/// variable interpolation or per-step failures.
ParsedReplayScript parseReplayScriptDetailed(String script) {
  final actions = <SessionAction>[];
  final actionLines = <int>[];
  final lines = script.split(RegExp(r'\r?\n'));
  var sawAction = false;
  for (var index = 0; index < lines.length; index++) {
    final raw = lines[index];
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (_isReplayEnvLine(trimmed)) {
      if (sawAction) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'env directives must precede all actions (line ${index + 1}).',
        );
      }
      continue;
    }
    final parsed = _parseReplayScriptLine(raw);
    if (parsed == null) continue;
    actions.add(parsed);
    actionLines.add(index + 1);
    sawAction = true;
  }
  return ParsedReplayScript(actions: actions, actionLines: actionLines);
}

/// Read metadata from the leading context header + env directives in
/// [script]. The leading context line carries platform/timeout/retries
/// kvs; standalone `env KEY=VALUE` lines populate the env map. We scan
/// the whole prelude (env directives can be interleaved with comments
/// before the context line) but stop at the first non-comment,
/// non-context, non-env line.
ReplayScriptMetadata readReplayScriptMetadata(String script) {
  final metadata = <String, Object?>{};
  final env = <String, String>{};
  final lines = script.split(RegExp(r'\r?\n'));
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (_isReplayEnvLine(trimmed)) {
      _ingestEnvLine(env, trimmed, index + 1);
      continue;
    }
    if (!trimmed.startsWith('context ')) break;

    final platformMatch = RegExp(
      r'(?:^|\s)platform=([^\s]+)',
    ).firstMatch(trimmed);
    if (platformMatch != null) {
      final platform = platformMatch.group(1);
      if (platform != null && _replayMetadataPlatforms.contains(platform)) {
        _assignReplayMetadataValue(metadata, 'platform', platform);
      }
    }

    final timeoutMatch = RegExp(r'(?:^|\s)timeout=(\d+)').firstMatch(trimmed);
    if (timeoutMatch != null) {
      final timeoutStr = timeoutMatch.group(1);
      if (timeoutStr != null) {
        final timeoutMs = int.tryParse(timeoutStr);
        if (timeoutMs != null && timeoutMs >= 1) {
          _assignReplayMetadataValue(metadata, 'timeoutMs', timeoutMs);
        }
      }
    }

    final retriesMatch = RegExp(r'(?:^|\s)retries=(\d+)').firstMatch(trimmed);
    if (retriesMatch != null) {
      final retriesStr = retriesMatch.group(1);
      if (retriesStr != null) {
        final retries = int.tryParse(retriesStr);
        if (retries != null && retries >= 0) {
          _assignReplayMetadataValue(metadata, 'retries', retries);
        }
      }
    }
  }

  return ReplayScriptMetadata(
    platform: metadata['platform'] as String?,
    timeoutMs: metadata['timeoutMs'] as int?,
    retries: metadata['retries'] as int?,
    env: env.isEmpty ? null : env,
  );
}

bool _isReplayEnvLine(String trimmed) =>
    trimmed == 'env' ||
    trimmed.startsWith('env ') ||
    trimmed.startsWith('env\t');

void _ingestEnvLine(
  Map<String, String> env,
  String trimmed,
  int lineNumber,
) {
  final body = trimmed.substring(3).trimLeft();
  final eqIndex = body.indexOf('=');
  if (eqIndex <= 0) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Invalid env directive on line $lineNumber: expected "env KEY=VALUE".',
    );
  }
  final key = body.substring(0, eqIndex);
  if (!replayVarKeyRe.hasMatch(key)) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Invalid env key "$key" on line $lineNumber: keys must be uppercase '
      'letters, digits, and underscores (e.g. APP_ID).',
    );
  }
  if (key.startsWith('AD_')) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Invalid env key "$key" on line $lineNumber: the AD_* namespace is '
      'reserved for built-in variables. Rename $key to avoid the AD_ prefix.',
    );
  }
  if (env.containsKey(key)) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Duplicate env directive "$key" on line $lineNumber.',
    );
  }
  env[key] = _decodeReplayEnvValue(body.substring(eqIndex + 1), lineNumber);
}

String _decodeReplayEnvValue(String raw, int lineNumber) {
  if (raw.isEmpty) return '';
  if (raw.startsWith('"')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! String) {
        throw const FormatException('not a string literal');
      }
      return decoded;
    } on FormatException {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid quoted env value on line $lineNumber.',
      );
    }
  }
  return raw;
}

/// Assign a metadata value, throwing if a conflicting value already exists.
void _assignReplayMetadataValue(
  Map<String, Object?> metadata,
  String key,
  Object value,
) {
  final previous = metadata[key];
  if (previous != null) {
    final duplicateMessage = previous == value
        ? 'Duplicate replay test metadata "$key" in context header.'
        : 'Conflicting replay test metadata "$key" in context header: $previous vs $value.';
    throw AppError(AppErrorCodes.invalidArgs, duplicateMessage);
  }
  metadata[key] = value;
}

/// Parse a single line from a replay script into a [SessionAction], or null if
/// the line is empty, a comment, or a context header.
SessionAction? _parseReplayScriptLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) return null;

  final tokens = _tokenizeReplayLine(trimmed);
  if (tokens.isEmpty) return null;

  final command = tokens[0];
  final args = tokens.sublist(1);

  if (command == 'context') return null;

  final action = SessionAction(
    ts: DateTime.now().millisecondsSinceEpoch,
    command: command,
    positionals: [],
    flags: {},
  );

  if (command == 'snapshot') {
    return _parseSnapshotAction(action, args);
  }

  if (command == 'open') {
    return _parseOpenAction(action, args);
  }

  if (command == 'runtime') {
    return _parseRuntimeAction(action, args);
  }

  if (isClickLikeCommand(command)) {
    return _parseClickLikeAction(action, args);
  }

  if (command == 'fill') {
    return _parseFillAction(action, args);
  }

  if (command == 'get') {
    return _parseGetAction(action, args);
  }

  if (command == 'swipe' || command == 'type') {
    return _parseSwipeOrTypeAction(action, args);
  }

  if (command == 'record') {
    return _parseRecordAction(action, args);
  }

  if (command == 'screenshot') {
    return _parseScreenshotAction(action, args);
  }

  action.flags; // access flags field from copyWith
  return action.copyWith(positionals: args);
}

/// Parse snapshot action flags: `-i`, `-c`, `-d <depth>`, `-s <scope>`, `--raw`.
SessionAction _parseSnapshotAction(SessionAction action, List<String> args) {
  final positionals = <String>[];
  for (int index = 0; index < args.length; index++) {
    final token = args[index];
    if (token == '-i') {
      action.flags['snapshotInteractiveOnly'] = true;
      continue;
    }
    if (token == '-c') {
      action.flags['snapshotCompact'] = true;
      continue;
    }
    if (token == '--raw') {
      action.flags['snapshotRaw'] = true;
      continue;
    }
    if ((token == '-d' || token == '--depth') && index + 1 < args.length) {
      final parsedDepth = int.tryParse(args[index + 1]);
      if (parsedDepth != null && parsedDepth >= 0) {
        action.flags['snapshotDepth'] = parsedDepth;
      }
      index++;
      continue;
    }
    if ((token == '-s' || token == '--scope') && index + 1 < args.length) {
      action.flags['snapshotScope'] = args[index + 1];
      index++;
      continue;
    }
    if (token == '--backend' && index + 1 < args.length) {
      // Backward compatibility: ignore legacy snapshot backend token.
      index++;
      continue;
    }
  }
  return action.copyWith(positionals: positionals);
}

/// Parse open action.
SessionAction _parseOpenAction(SessionAction action, List<String> args) {
  final parsed = parseReplayOpenFlags(args);
  final newAction = action.copyWith(
    positionals: parsed.positionals,
    flags: {...action.flags, ...parsed.flags},
    runtime: parsed.runtime,
  );
  return newAction;
}

/// Parse runtime action.
SessionAction _parseRuntimeAction(SessionAction action, List<String> args) {
  final parsed = parseReplayRuntimeFlags(args);
  return action.copyWith(
    positionals: parsed.positionals,
    flags: {...action.flags, ...parsed.flags},
  );
}

/// Parse click-like action (click/press).
SessionAction _parseClickLikeAction(SessionAction action, List<String> args) {
  final parsed = parseReplaySeriesFlags(action.command, args);
  final newFlags = {...action.flags, ...parsed.flags};

  if (parsed.positionals.isEmpty) {
    return action.copyWith(flags: newFlags);
  }

  final target = parsed.positionals[0];
  if (target.startsWith('@')) {
    final positionals = [target];
    final result = parsed.positionals.length > 1
        ? {'refLabel': parsed.positionals[1]}
        : null;
    return action.copyWith(
      positionals: positionals,
      flags: newFlags,
      result: result,
    );
  }

  final maybeX = parsed.positionals[0];
  final maybeY = parsed.positionals.length > 1 ? parsed.positionals[1] : null;
  if (_isNumericToken(maybeX) && _isNumericToken(maybeY)) {
    return action.copyWith(positionals: [maybeX, maybeY!], flags: newFlags);
  }

  return action.copyWith(
    positionals: [parsed.positionals.join(' ')],
    flags: newFlags,
  );
}

/// Parse fill action.
SessionAction _parseFillAction(SessionAction action, List<String> args) {
  final parsed = parseReplaySeriesFlags(action.command, args);
  final newFlags = {...action.flags, ...parsed.flags};

  if (parsed.positionals.length < 2) {
    return action.copyWith(positionals: parsed.positionals, flags: newFlags);
  }

  final target = parsed.positionals[0];
  if (target.startsWith('@')) {
    if (parsed.positionals.length >= 3) {
      return action.copyWith(
        positionals: [target, parsed.positionals.sublist(2).join(' ')],
        flags: newFlags,
        result: {'refLabel': parsed.positionals[1]},
      );
    }
    final secondPos = parsed.positionals.length > 1
        ? parsed.positionals[1]
        : '';
    return action.copyWith(positionals: [target, secondPos], flags: newFlags);
  }

  return action.copyWith(
    positionals: [target, parsed.positionals.sublist(1).join(' ')],
    flags: newFlags,
  );
}

/// Parse get action.
SessionAction _parseGetAction(SessionAction action, List<String> args) {
  if (args.length < 2) {
    return action.copyWith(positionals: args);
  }

  final sub = args[0];
  final target = args[1];
  if (target.startsWith('@')) {
    final result = args.length > 2 ? {'refLabel': args[2]} : null;
    return action.copyWith(positionals: [sub, target], result: result);
  }

  return action.copyWith(positionals: [sub, args.sublist(1).join(' ')]);
}

/// Parse swipe or type action.
SessionAction _parseSwipeOrTypeAction(SessionAction action, List<String> args) {
  final parsed = parseReplaySeriesFlags(action.command, args);
  return action.copyWith(
    positionals: parsed.positionals,
    flags: {...action.flags, ...parsed.flags},
  );
}

/// Parse record action.
SessionAction _parseRecordAction(SessionAction action, List<String> args) {
  final positionals = <String>[];
  final flags = <String, Object?>{};

  for (int index = 0; index < args.length; index++) {
    final token = args[index];
    if (token == '--hide-touches') {
      flags['hideTouches'] = true;
      continue;
    }
    if (token == '--fps' && index + 1 < args.length) {
      final parsedFps = int.tryParse(args[index + 1]);
      if (parsedFps != null) {
        flags['fps'] = parsedFps;
      }
      index++;
      continue;
    }
    if (token == '--quality' && index + 1 < args.length) {
      final parsedQuality = int.tryParse(args[index + 1]);
      if (parsedQuality != null) {
        flags['quality'] = parsedQuality;
      }
      index++;
      continue;
    }
    positionals.add(token);
  }

  return action.copyWith(
    positionals: positionals,
    flags: {...action.flags, ...flags},
  );
}

/// Parse screenshot action.
SessionAction _parseScreenshotAction(SessionAction action, List<String> args) {
  final positionals = <String>[];
  final flags = <String, Object?>{};

  for (int index = 0; index < args.length; index++) {
    final token = args[index];
    if (token == '--fullscreen') {
      flags['screenshotFullscreen'] = true;
      continue;
    }
    if (token == '--max-size') {
      final value = index + 1 < args.length ? args[index + 1] : null;
      final maxSize = value != null ? int.tryParse(value) : null;
      if (maxSize == null || maxSize < 1) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'screenshot --max-size requires a positive integer',
        );
      }
      flags['screenshotMaxSize'] = maxSize;
      index++;
      continue;
    }
    positionals.add(token);
  }

  return action.copyWith(
    positionals: positionals,
    flags: {...action.flags, ...flags},
  );
}

/// True if [token] is a numeric string.
bool _isNumericToken(String? token) {
  if (token == null) return false;
  return double.tryParse(token) != null;
}

/// Tokenize a replay script line, handling quoted strings and escapes.
/// Throws [AppError] if quoting is malformed.
List<String> _tokenizeReplayLine(String line) {
  final tokens = <String>[];
  int cursor = 0;

  while (cursor < line.length) {
    // Skip whitespace
    while (cursor < line.length && _isWhitespace(line[cursor])) {
      cursor++;
    }
    if (cursor >= line.length) break;

    if (line[cursor] == '"') {
      // Parse quoted string
      int end = cursor + 1;
      bool escaped = false;
      while (end < line.length) {
        final char = line[end];
        if (char == '"' && !escaped) break;
        escaped = char == '\\' && !escaped;
        if (char != '\\') escaped = false;
        end++;
      }
      if (end >= line.length) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'Invalid replay script line: $line',
        );
      }
      final literal = line.substring(cursor, end + 1);
      try {
        tokens.add(_parseJsonString(literal));
      } catch (e) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'Invalid JSON string in replay script: $literal',
        );
      }
      cursor = end + 1;
      continue;
    }

    // Parse unquoted token
    int end = cursor;
    while (end < line.length && !_isWhitespace(line[end])) {
      end++;
    }
    tokens.add(line.substring(cursor, end));
    cursor = end;
  }

  return tokens;
}

/// Check if a character is whitespace.
bool _isWhitespace(String char) {
  return RegExp(r'\s').hasMatch(char);
}

/// Parse a JSON string literal (including the surrounding quotes).
/// Delegates to `jsonDecode` so the full escape grammar works —
/// `\n`, `\t`, `\u00XX`, etc. — not just the bare-minimum `\"` / `\\`
/// the earlier hand-written stub covered.
String _parseJsonString(String literal) {
  if (!literal.startsWith('"') || !literal.endsWith('"')) {
    throw FormatException('Not a JSON string: $literal');
  }
  final decoded = jsonDecode(literal);
  if (decoded is! String) {
    throw FormatException('Not a JSON string literal: $literal');
  }
  return decoded;
}

/// Format a replay action back into a script line.
String formatReplayActionLine(SessionAction action) {
  final parts = <String>[action.command];

  if (action.command == 'snapshot') {
    if (action.flags['snapshotInteractiveOnly'] == true) parts.add('-i');
    if (action.flags['snapshotCompact'] == true) parts.add('-c');
    if (action.flags['snapshotDepth'] is int) {
      parts.add('-d');
      parts.add((action.flags['snapshotDepth'] as int).toString());
    }
    if (action.flags['snapshotScope'] is String) {
      parts.add('-s');
      parts.add(formatScriptArg(action.flags['snapshotScope'] as String));
    }
    if (action.flags['snapshotRaw'] == true) parts.add('--raw');
    return parts.join(' ');
  }

  if (action.command == 'open') {
    appendOpenActionScriptArgs(parts, action);
    return parts.join(' ');
  }

  if (action.command == 'runtime') {
    for (final positional in action.positionals) {
      parts.add(formatScriptArgQuoteIfNeeded(positional));
    }
    appendRuntimeHintFlags(parts, action.flags);
    return parts.join(' ');
  }

  if (action.command == 'record') {
    appendRecordActionScriptArgs(parts, action);
    return parts.join(' ');
  }

  if (action.command == 'screenshot') {
    for (final positional in action.positionals) {
      parts.add(formatScriptArg(positional));
    }
    if (action.flags['screenshotFullscreen'] == true) parts.add('--fullscreen');
    if (action.flags['screenshotMaxSize'] is int) {
      parts.add('--max-size');
      parts.add((action.flags['screenshotMaxSize'] as int).toString());
    }
    return parts.join(' ');
  }

  // Generic command: format positionals and append series flags
  for (final positional in action.positionals) {
    parts.add(formatScriptArg(positional));
  }
  appendScriptSeriesFlags(parts, action);
  return parts.join(' ');
}

/// Serialize a list of [SessionAction]s back into a replay script string.
/// If [session] is provided, includes a context header line.
/// TODO(port): session parameter is not ported (SessionState is huge);
/// callers construct the context line themselves if needed.
String serializeReplayScript(
  List<SessionAction> actions, {
  String? contextLine,
}) {
  final lines = <String>[];
  if (contextLine != null) {
    lines.add(contextLine);
  }
  for (final action in actions) {
    lines.add(formatReplayActionLine(action));
  }
  return '${lines.join('\n')}\n';
}
