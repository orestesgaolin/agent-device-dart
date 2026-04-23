// Port of agent-device/src/daemon/selectors-parse.ts
library;

import 'package:agent_device/src/utils/errors.dart';

/// Supported selector keys (both text and boolean).
typedef SelectorKey = String;

/// A single key-value term in a selector.
class SelectorTerm {
  final SelectorKey key;
  final Object value; // String or bool

  const SelectorTerm({required this.key, required this.value});
}

/// A single selector expression (one alternative in a chain).
class Selector {
  final String raw;
  final List<SelectorTerm> terms;

  const Selector({required this.raw, required this.terms});
}

/// A chain of selectors (separated by ||).
class SelectorChain {
  final String raw;
  final List<Selector> selectors;

  const SelectorChain({required this.raw, required this.selectors});
}

const _textKeys = {
  'id',
  'role',
  'text',
  'label',
  'value',
  'appname',
  'windowtitle',
};

const _booleanKeys = {
  'visible',
  'hidden',
  'editable',
  'selected',
  'enabled',
  'hittable',
};

/// Parse a selector expression into a chain of alternatives.
SelectorChain parseSelectorChain(String expression) {
  final raw = expression.trim();
  if (raw.isEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Selector expression cannot be empty',
    );
  }
  final segments = _splitByFallback(raw);
  if (segments.isEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Selector expression cannot be empty',
    );
  }
  return SelectorChain(
    raw: raw,
    selectors: segments.map(_parseSelector).toList(),
  );
}

/// Try to parse a selector chain, returning null on error.
SelectorChain? tryParseSelectorChain(String expression) {
  try {
    return parseSelectorChain(expression);
  } catch (_) {
    return null;
  }
}

/// Check if a token is a valid selector token.
bool isSelectorToken(String token) {
  final trimmed = token.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed == '||') return true;
  final equalsIdx = trimmed.indexOf('=');
  if (equalsIdx != -1) {
    final key = trimmed.substring(0, equalsIdx).trim().toLowerCase();
    return _textKeys.contains(key) || _booleanKeys.contains(key);
  }
  return _textKeys.contains(trimmed.toLowerCase()) ||
      _booleanKeys.contains(trimmed.toLowerCase());
}

/// Split selector from remaining arguments.
({String selectorExpression, List<String> rest})? splitSelectorFromArgs(
  List<String> args, {
  bool preferTrailingValue = false,
}) {
  if (args.isEmpty) return null;
  var i = 0;
  final boundaries = <int>[];
  while (i < args.length && isSelectorToken(args[i])) {
    i += 1;
    final candidate = args.sublist(0, i).join(' ').trim();
    if (candidate.isEmpty) continue;
    if (tryParseSelectorChain(candidate) != null) {
      boundaries.add(i);
    }
  }
  if (boundaries.isEmpty) return null;
  var boundary = boundaries.last;
  if (preferTrailingValue) {
    for (var i = boundaries.length - 1; i >= 0; i -= 1) {
      if (boundaries[i] < args.length) {
        boundary = boundaries[i];
        break;
      }
    }
  }
  final selectorExpression = args.sublist(0, boundary).join(' ').trim();
  if (selectorExpression.isEmpty) return null;
  return (selectorExpression: selectorExpression, rest: args.sublist(boundary));
}

/// Split arguments for an 'is' predicate.
({String predicate, ({String selectorExpression, List<String> rest})? split})
splitIsSelectorArgs(List<String> positionals) {
  final predicate = positionals.isNotEmpty ? positionals[0] : '';
  final split = positionals.length > 1
      ? splitSelectorFromArgs(
          positionals.sublist(1),
          preferTrailingValue: predicate == 'text',
        )
      : null;
  return (predicate: predicate, split: split);
}

/// Parse a single selector segment.
Selector _parseSelector(String segment) {
  final raw = segment.trim();
  if (raw.isEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Selector segment cannot be empty',
    );
  }
  final tokens = _tokenize(raw);
  if (tokens.isEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Invalid selector segment: $segment',
    );
  }
  return Selector(raw: raw, terms: tokens.map(_parseTerm).toList());
}

/// Parse a single term token.
SelectorTerm _parseTerm(String token) {
  final normalized = token.trim();
  if (normalized.isEmpty) {
    throw AppError(AppErrorCodes.invalidArgs, 'Empty selector term');
  }
  final equalsIdx = normalized.indexOf('=');
  if (equalsIdx == -1) {
    final key = normalized.toLowerCase();
    if (!_booleanKeys.contains(key)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid selector term "$token", expected key=value',
      );
    }
    return SelectorTerm(key: key, value: true);
  }
  final key = normalized.substring(0, equalsIdx).trim().toLowerCase();
  final valueRaw = normalized.substring(equalsIdx + 1).trim();
  if (!_textKeys.contains(key) && !_booleanKeys.contains(key)) {
    throw AppError(AppErrorCodes.invalidArgs, 'Unknown selector key: $key');
  }
  if (valueRaw.isEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Missing selector value for key: $key',
    );
  }
  if (_booleanKeys.contains(key)) {
    final value = _parseBoolean(valueRaw);
    if (value == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid boolean value for $key: $valueRaw',
      );
    }
    return SelectorTerm(key: key, value: value);
  }
  return SelectorTerm(key: key, value: _unquote(valueRaw));
}

/// Split expression by fallback operator (||).
List<String> _splitByFallback(String expression) {
  final segments = <String>[];
  var current = '';
  String? quote;
  for (var i = 0; i < expression.length; i += 1) {
    final ch = expression[i];
    if ((ch == '"' || ch == "'") && !_isEscapedQuote(expression, i)) {
      quote = _updateQuoteState(quote, ch);
      current += ch;
      continue;
    }
    if (quote == null &&
        ch == '|' &&
        i + 1 < expression.length &&
        expression[i + 1] == '|') {
      final segment = current.trim();
      if (segment.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'Invalid selector fallback expression: $expression',
        );
      }
      segments.add(segment);
      current = '';
      i += 1;
      continue;
    }
    current += ch;
  }
  final finalSegment = current.trim();
  if (finalSegment.isEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Invalid selector fallback expression: $expression',
    );
  }
  segments.add(finalSegment);
  return segments;
}

/// Tokenize a selector segment into terms.
List<String> _tokenize(String segment) {
  final tokens = <String>[];
  var current = '';
  String? quote;
  for (var i = 0; i < segment.length; i += 1) {
    final ch = segment[i];
    if ((ch == '"' || ch == "'") && !_isEscapedQuote(segment, i)) {
      quote = _updateQuoteState(quote, ch);
      current += ch;
      continue;
    }
    if (quote == null && RegExp(r'\s').hasMatch(ch)) {
      if (current.trim().isNotEmpty) tokens.add(current.trim());
      current = '';
      continue;
    }
    current += ch;
  }
  if (quote != null) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Unclosed quote in selector: $segment',
    );
  }
  if (current.trim().isNotEmpty) tokens.add(current.trim());
  return tokens;
}

/// Update quote state when encountering a quote character.
String? _updateQuoteState(String? currentQuote, String ch) {
  if (currentQuote == null) return ch;
  return currentQuote == ch ? null : currentQuote;
}

/// Unquote a string value.
String _unquote(String value) {
  final trimmed = value.trim();
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    final unquoted = trimmed.substring(1, trimmed.length - 1);
    // Replace escaped quotes with the quote character
    return unquoted
        .replaceAll(RegExp(r'\\"'), '"')
        .replaceAll(RegExp(r"\\'"), "'");
  }
  return trimmed;
}

/// Parse a boolean value.
bool? _parseBoolean(String value) {
  final normalized = _unquote(value).toLowerCase();
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;
  return null;
}

/// Check if a quote at a position is escaped.
bool _isEscapedQuote(String source, int index) {
  var backslashCount = 0;
  for (var i = index - 1; i >= 0 && source[i] == '\\'; i -= 1) {
    backslashCount += 1;
  }
  return backslashCount % 2 == 1;
}
