/// Port of `agent-device/src/daemon/script-utils.ts`.
/// Helpers for formatting and parsing replay script arguments, flags, and series.
library;

import 'session_action.dart';

final _numericArgRe = RegExp(r'^-?\d+(\.\d+)?$');
final _bareScriptTokenRe = RegExp(r'^[^\s"\\]+$');

/// Map of click/press flag names to their key in SessionAction.flags.
const _clickLikeNumericFlagMap = {
  '--count': 'count',
  '--interval-ms': 'intervalMs',
  '--hold-ms': 'holdMs',
  '--jitter-px': 'jitterPx',
};

/// Map of swipe flag names to their key in SessionAction.flags.
const _swipeNumericFlagMap = {'--count': 'count', '--pause-ms': 'pauseMs'};

/// Map of type/fill flag names to their key in SessionAction.flags.
const _typingNumericFlagMap = {'--delay-ms': 'delayMs'};

/// True if [command] is a click-like command ('click' or 'press').
bool isClickLikeCommand(String command) {
  return command == 'click' || command == 'press';
}

/// True if [command] is a typing command ('type' or 'fill').
bool _isTypingCommand(String command) {
  return command == 'type' || command == 'fill';
}

/// Format a script argument, quoting as needed if it contains special chars.
String formatScriptArg(String value) {
  return _formatScriptToken(value, _isStructuralScriptToken);
}

/// Format a string literal (always quoted for JSON-safe round-trip).
String formatScriptStringLiteral(String value) {
  // Use Dart's built-in JSON encoding via jsonEncode.
  // Since we need just the quoted string, we'll do it manually to match JS:
  return '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}

/// Format a script argument, only quoting if needed (readable for ordinary tokens).
String formatScriptArgQuoteIfNeeded(String value) {
  return _formatScriptToken(value, _isBareScriptToken);
}

String _formatScriptToken(String value, bool Function(String) canStayBare) {
  return canStayBare(value) ? value : formatScriptStringLiteral(value);
}

/// True if [value] is a structural token (e.g., selector ref or numeric).
bool _isStructuralScriptToken(String value) {
  return (_isBareScriptToken(value) && value.startsWith('@')) ||
      _numericArgRe.hasMatch(value);
}

/// True if [value] can stay bare (no quotes needed).
bool _isBareScriptToken(String value) {
  return _bareScriptTokenRe.hasMatch(value);
}

/// Format an action as a one-line summary: `command arg1 arg2 ...`.
String formatScriptActionSummary(SessionAction action) {
  final values = (action.positionals)
      .map((value) => formatScriptArg(value))
      .toList();
  return [action.command, ...values].join(' ');
}

/// Append series-specific flags (click/swipe/type) to [parts] based on [action].
void appendScriptSeriesFlags(List<String> parts, SessionAction action) {
  final flags = action.flags;
  if (isClickLikeCommand(action.command)) {
    if (flags['count'] is int) {
      parts.add('--count');
      parts.add((flags['count'] as int).toString());
    }
    if (flags['intervalMs'] is int) {
      parts.add('--interval-ms');
      parts.add((flags['intervalMs'] as int).toString());
    }
    if (flags['holdMs'] is int) {
      parts.add('--hold-ms');
      parts.add((flags['holdMs'] as int).toString());
    }
    if (flags['jitterPx'] is int) {
      parts.add('--jitter-px');
      parts.add((flags['jitterPx'] as int).toString());
    }
    if (flags['doubleTap'] == true) {
      parts.add('--double-tap');
    }
    final clickButton = flags['clickButton'];
    if (clickButton is String && clickButton != 'primary') {
      parts.add('--button');
      parts.add(clickButton);
    }
    return;
  }
  if (action.command == 'swipe') {
    if (flags['count'] is int) {
      parts.add('--count');
      parts.add((flags['count'] as int).toString());
    }
    if (flags['pauseMs'] is int) {
      parts.add('--pause-ms');
      parts.add((flags['pauseMs'] as int).toString());
    }
    final pattern = flags['pattern'];
    if (pattern == 'one-way' || pattern == 'ping-pong') {
      parts.add('--pattern');
      parts.add(pattern as String);
    }
    return;
  }
  if (_isTypingCommand(action.command)) {
    if (flags['delayMs'] is int) {
      parts.add('--delay-ms');
      parts.add((flags['delayMs'] as int).toString());
    }
  }
}

/// Append runtime hint flags (platform, metro config, etc.) to [parts].
void appendRuntimeHintFlags(List<String> parts, Map<String, Object?>? flags) {
  if (flags == null) return;
  final platform = flags['platform'];
  if (platform == 'ios' || platform == 'android') {
    parts.add('--platform');
    parts.add(platform as String);
  }
  final metroHost = flags['metroHost'];
  if (metroHost is String && metroHost.isNotEmpty) {
    parts.add('--metro-host');
    parts.add(formatScriptArgQuoteIfNeeded(metroHost));
  }
  final metroPort = flags['metroPort'];
  if (metroPort is int) {
    parts.add('--metro-port');
    parts.add(metroPort.toString());
  }
  final bundleUrl = flags['bundleUrl'];
  if (bundleUrl is String && bundleUrl.isNotEmpty) {
    parts.add('--bundle-url');
    parts.add(formatScriptArgQuoteIfNeeded(bundleUrl));
  }
  final launchUrl = flags['launchUrl'];
  if (launchUrl is String && launchUrl.isNotEmpty) {
    parts.add('--launch-url');
    parts.add(formatScriptArgQuoteIfNeeded(launchUrl));
  }
}

/// Append record action script args (fps, quality, hide-touches) to [parts].
void appendRecordActionScriptArgs(List<String> parts, SessionAction action) {
  final positionals = action.positionals;
  if (positionals.isNotEmpty) {
    parts.add(formatScriptArgQuoteIfNeeded(positionals[0]));
  }
  for (int i = 1; i < positionals.length; i++) {
    parts.add(formatScriptArg(positionals[i]));
  }
  final flags = action.flags;
  if (flags['fps'] is int) {
    parts.add('--fps');
    parts.add((flags['fps'] as int).toString());
  }
  if (flags['quality'] is int) {
    parts.add('--quality');
    parts.add((flags['quality'] as int).toString());
  }
  if (flags['hideTouches'] == true) {
    parts.add('--hide-touches');
  }
}

/// Parse series-specific flags (click/swipe/type) from [args].
/// Returns a tuple of (positionals, flags).
({List<String> positionals, Map<String, Object?> flags}) parseReplaySeriesFlags(
  String command,
  List<String> args,
) {
  final positionals = <String>[];
  final flags = <String, Object?>{};

  final numericFlagMap = isClickLikeCommand(command)
      ? _clickLikeNumericFlagMap
      : command == 'swipe'
      ? _swipeNumericFlagMap
      : _isTypingCommand(command)
      ? _typingNumericFlagMap
      : <String, String>{};

  for (int index = 0; index < args.length; index++) {
    final token = args[index];

    if (isClickLikeCommand(command) && token == '--double-tap') {
      flags['doubleTap'] = true;
      continue;
    }
    if (isClickLikeCommand(command) &&
        token == '--button' &&
        index + 1 < args.length) {
      final clickButton = args[index + 1];
      if (clickButton == 'primary' ||
          clickButton == 'secondary' ||
          clickButton == 'middle') {
        flags['clickButton'] = clickButton;
      }
      index++;
      continue;
    }

    final numericKey = numericFlagMap[token];
    if (numericKey != null && index + 1 < args.length) {
      final parsed = _parseNonNegativeIntToken(args[index + 1]);
      if (parsed != null) {
        flags[numericKey] = parsed;
        index++;
        continue;
      }
    }

    if (command == 'swipe' && token == '--pattern' && index + 1 < args.length) {
      final pattern = args[index + 1];
      if (pattern == 'one-way' || pattern == 'ping-pong') {
        flags['pattern'] = pattern;
      }
      index++;
      continue;
    }

    positionals.add(token);
  }

  return (positionals: positionals, flags: flags);
}

/// Parse runtime hint flags from [args].
/// Returns a tuple of (positionals, flags).
({List<String> positionals, Map<String, Object?> flags})
parseReplayRuntimeFlags(List<String> args) {
  final positionals = <String>[];
  final flags = <String, Object?>{};

  for (int index = 0; index < args.length; index++) {
    final token = args[index];
    if (token == '--platform' && index + 1 < args.length) {
      final platform = args[index + 1];
      if (platform == 'ios' || platform == 'android') {
        flags['platform'] = platform;
      }
      index++;
      continue;
    }
    if (token == '--metro-host' && index + 1 < args.length) {
      flags['metroHost'] = args[index + 1];
      index++;
      continue;
    }
    if (token == '--metro-port' && index + 1 < args.length) {
      final parsed = _parseNonNegativeIntToken(args[index + 1]);
      if (parsed != null) {
        flags['metroPort'] = parsed;
      }
      index++;
      continue;
    }
    if (token == '--bundle-url' && index + 1 < args.length) {
      flags['bundleUrl'] = args[index + 1];
      index++;
      continue;
    }
    if (token == '--launch-url' && index + 1 < args.length) {
      flags['launchUrl'] = args[index + 1];
      index++;
      continue;
    }
    positionals.add(token);
  }

  return (positionals: positionals, flags: flags);
}

/// Parse a token as a non-negative integer, or null if invalid.
int? _parseNonNegativeIntToken(String? token) {
  if (token == null) return null;
  final value = int.tryParse(token);
  if (value == null || value < 0) return null;
  return value;
}
