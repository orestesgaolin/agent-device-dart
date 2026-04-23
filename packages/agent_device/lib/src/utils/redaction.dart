/// Port of `agent-device/src/utils/redaction.ts`.
///
/// Redacts sensitive data from diagnostic payloads (tokens, passwords, keys)
/// before they are written to logs or surfaced in error output.
library;

final RegExp _sensitiveKeyRe = RegExp(
  r'(token|secret|password|authorization|cookie|api[_-]?key|access[_-]?key|private[_-]?key)',
  caseSensitive: false,
);

final RegExp _sensitiveValueRe = RegExp(
  r'(bearer\s+[a-z0-9._-]+|(?:api[_-]?key|token|secret|password)\s*[=:]\s*\S+)',
  caseSensitive: false,
);

/// Recursively redact sensitive fields in [input]. Strings are checked for
/// sensitive substrings; map keys matching sensitive names are replaced with
/// `[REDACTED]`. URLs with credentials or query strings are partially masked.
/// Circular references are replaced with the string `[Circular]`.
Object? redactDiagnosticData(Object? input) {
  return _redactValue(input, Set<int>.identity());
}

Object? _redactValue(Object? value, Set<int> seen, {String? keyHint}) {
  if (value == null) return value;
  if (value is String) return _redactString(value, keyHint);
  if (value is num || value is bool) return value;

  final id = identityHashCode(value);
  if (seen.contains(id)) return '[Circular]';
  seen.add(id);

  if (value is List) {
    return value.map((entry) => _redactValue(entry, seen)).toList();
  }
  if (value is Map) {
    final output = <String, Object?>{};
    value.forEach((key, entry) {
      final keyStr = key.toString();
      if (_sensitiveKeyRe.hasMatch(keyStr)) {
        output[keyStr] = '[REDACTED]';
      } else {
        output[keyStr] = _redactValue(entry, seen, keyHint: keyStr);
      }
    });
    return output;
  }
  return value;
}

String _redactString(String value, String? keyHint) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return value;
  if (keyHint != null && _sensitiveKeyRe.hasMatch(keyHint)) return '[REDACTED]';
  if (_sensitiveValueRe.hasMatch(trimmed)) return '[REDACTED]';
  final masked = _redactUrl(trimmed);
  if (masked != null) return masked;
  if (trimmed.length > 400) {
    return '${trimmed.substring(0, 200)}...<truncated>';
  }
  return trimmed;
}

String? _redactUrl(String value) {
  final Uri parsed;
  try {
    parsed = Uri.parse(value);
  } catch (_) {
    return null;
  }
  // Heuristic: only treat as a URL if it has a scheme and authority, to match
  // `new URL(value)` behavior in Node which rejects bare paths.
  if (!parsed.hasScheme || !parsed.hasAuthority) return null;
  final hasQuery = parsed.hasQuery;
  final hasCreds = parsed.userInfo.isNotEmpty;
  if (!hasQuery && !hasCreds) return parsed.toString();
  final rebuilt = parsed.replace(
    userInfo: hasCreds ? 'REDACTED:REDACTED' : null,
    query: hasQuery ? 'REDACTED' : null,
  );
  return rebuilt.toString();
}
