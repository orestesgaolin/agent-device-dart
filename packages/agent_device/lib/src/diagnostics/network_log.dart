// Port of agent-device/src/daemon/network-log.ts.
//
// Pure text parser that extracts HTTP request/response activity from an
// app-log dump. Works on both structured (JSON-ish) and unstructured
// logcat / os_log lines. Android gets extra cross-line correlation so
// OkHttp-style interceptor output whose pieces span several lines still
// produces complete entries.
library;

import 'dart:convert';
import 'dart:io';

/// How much of each HTTP entry to include in the result.
enum NetworkIncludeMode {
  summary,
  headers,
  body,
  all;

  static NetworkIncludeMode parse(String? raw) {
    return switch (raw) {
      'summary' => NetworkIncludeMode.summary,
      'headers' => NetworkIncludeMode.headers,
      'body' => NetworkIncludeMode.body,
      'all' => NetworkIncludeMode.all,
      _ => NetworkIncludeMode.summary,
    };
  }

  String get value => switch (this) {
    NetworkIncludeMode.summary => 'summary',
    NetworkIncludeMode.headers => 'headers',
    NetworkIncludeMode.body => 'body',
    NetworkIncludeMode.all => 'all',
  };
}

/// Which backend produced the log file (affects Android-specific
/// cross-line enrichment).
enum NetworkLogBackend {
  iosSimulator('ios-simulator'),
  iosDevice('ios-device'),
  android('android'),
  macos('macos');

  final String wire;
  const NetworkLogBackend(this.wire);

  static NetworkLogBackend? parse(String? raw) {
    if (raw == null) return null;
    for (final b in NetworkLogBackend.values) {
      if (b.wire == raw) return b;
    }
    return null;
  }
}

class NetworkEntry {
  final String? method;
  final String url;
  final int? status;
  final String? timestamp;
  final int? durationMs;
  final String? packetId;
  final String? headers;
  final String? requestBody;
  final String? responseBody;
  final String raw;
  final int line;

  const NetworkEntry({
    required this.url,
    required this.raw,
    required this.line,
    this.method,
    this.status,
    this.timestamp,
    this.durationMs,
    this.packetId,
    this.headers,
    this.requestBody,
    this.responseBody,
  });

  NetworkEntry copyWith({
    String? method,
    int? status,
    String? timestamp,
    int? durationMs,
    String? packetId,
    String? headers,
    String? requestBody,
    String? responseBody,
  }) => NetworkEntry(
    url: url,
    raw: raw,
    line: line,
    method: method ?? this.method,
    status: status ?? this.status,
    timestamp: timestamp ?? this.timestamp,
    durationMs: durationMs ?? this.durationMs,
    packetId: packetId ?? this.packetId,
    headers: headers ?? this.headers,
    requestBody: requestBody ?? this.requestBody,
    responseBody: responseBody ?? this.responseBody,
  );

  Map<String, Object?> toJson() => {
    if (method != null) 'method': method,
    'url': url,
    if (status != null) 'status': status,
    if (timestamp != null) 'timestamp': timestamp,
    if (durationMs != null) 'durationMs': durationMs,
    if (packetId != null) 'packetId': packetId,
    if (headers != null) 'headers': headers,
    if (requestBody != null) 'requestBody': requestBody,
    if (responseBody != null) 'responseBody': responseBody,
    'raw': raw,
    'line': line,
  };
}

class NetworkDumpLimits {
  final int maxEntries;
  final int maxPayloadChars;
  final int maxScanLines;
  const NetworkDumpLimits({
    required this.maxEntries,
    required this.maxPayloadChars,
    required this.maxScanLines,
  });

  Map<String, Object?> toJson() => {
    'maxEntries': maxEntries,
    'maxPayloadChars': maxPayloadChars,
    'maxScanLines': maxScanLines,
  };
}

class NetworkDump {
  final String path;
  final bool exists;
  final int scannedLines;
  final int matchedLines;
  final List<NetworkEntry> entries;
  final NetworkIncludeMode include;
  final NetworkDumpLimits limits;

  const NetworkDump({
    required this.path,
    required this.exists,
    required this.scannedLines,
    required this.matchedLines,
    required this.entries,
    required this.include,
    required this.limits,
  });

  Map<String, Object?> toJson() => {
    'path': path,
    'exists': exists,
    'scannedLines': scannedLines,
    'matchedLines': matchedLines,
    'entries': entries.map((e) => e.toJson()).toList(),
    'include': include.value,
    'limits': limits.toJson(),
  };
}

/// Clamp a possibly-null int into [min, max] with a fallback.
int _clampInt(int? value, int fallback, int min, int max) {
  if (value == null) return fallback;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

const _httpMethods = [
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
];
final RegExp _methodWithUrlRegex = RegExp(
  r'\b(' + _httpMethods.join('|') + r')\b\s+https?:\/\/',
  caseSensitive: false,
);
final RegExp _urlRegex = RegExp(
  r'''https?:\/\/[^\s"'<>\])]+''',
  caseSensitive: false,
);
final List<RegExp> _statusPatterns = [
  RegExp(r'''\bstatus(?:Code)?["'=: ]+([1-5]\d{2})\b''', caseSensitive: false),
  RegExp(
    r'''\bresponse(?:\s+code)?["'=: ]+([1-5]\d{2})\b''',
    caseSensitive: false,
  ),
  RegExp(r'\bHTTP\/[0-9.]+\s+([1-5]\d{2})\b', caseSensitive: false),
];
final RegExp _methodFieldRegex = RegExp(
  r'''\bmethod["'=: ]+([A-Z]+)\b''',
  caseSensitive: false,
);
final RegExp _urlFieldRegex = RegExp(
  r'''\bURL["'=: ]+https?:\/\/''',
  caseSensitive: false,
);
final RegExp _headersFieldRegex = RegExp(
  r'''\bheaders?["'=: ]+''',
  caseSensitive: false,
);
final RegExp _bodyFieldRegex = RegExp(
  r'''\b(?:requestBody|responseBody|payload|request|response)["'=: ]+''',
  caseSensitive: false,
);
final RegExp _headersJsonRegex = RegExp(
  r'''\bheaders?["'=: ]+(\{.*\})''',
  caseSensitive: false,
);
final RegExp _isoTimestampRegex = RegExp(
  r'\b\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z)?\b',
);
final RegExp _androidTimestampRegex = RegExp(
  r'\b\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+\b',
);
final RegExp _androidPacketIdRegex = RegExp(
  r'\bpacket id (\d+)\b',
  caseSensitive: false,
);
final RegExp _androidDurationRegex = RegExp(
  r'\b(?:duration|elapsed request\/response time, ms)[:= ]+(\d+)\b',
  caseSensitive: false,
);

const int _androidNearbyLineRadius = 5;
const int _androidPacketScanRadius = 12;

/// Scan the tail of [logPath] and extract up to [maxEntries] most-recent
/// HTTP request/response entries.
NetworkDump readRecentNetworkTraffic(
  String logPath, {
  NetworkLogBackend? backend,
  int? maxEntries,
  NetworkIncludeMode include = NetworkIncludeMode.summary,
  int? maxPayloadChars,
  int? maxScanLines,
}) {
  final clampedMaxEntries = _clampInt(maxEntries, 25, 1, 200);
  final clampedMaxPayloadChars = _clampInt(maxPayloadChars, 2048, 64, 16384);
  final clampedMaxScanLines = _clampInt(maxScanLines, 4000, 100, 20000);
  final limits = NetworkDumpLimits(
    maxEntries: clampedMaxEntries,
    maxPayloadChars: clampedMaxPayloadChars,
    maxScanLines: clampedMaxScanLines,
  );
  final file = File(logPath);
  if (!file.existsSync()) {
    return NetworkDump(
      path: logPath,
      exists: false,
      scannedLines: 0,
      matchedLines: 0,
      entries: const [],
      include: include,
      limits: limits,
    );
  }
  final content = file.readAsStringSync();
  return readRecentNetworkTrafficFromText(
    content,
    path: logPath,
    backend: backend,
    maxEntries: maxEntries,
    include: include,
    maxPayloadChars: maxPayloadChars,
    maxScanLines: maxScanLines,
  );
}

/// Same as [readRecentNetworkTraffic] but on an in-memory string.
NetworkDump readRecentNetworkTrafficFromText(
  String content, {
  String? path,
  NetworkLogBackend? backend,
  int? maxEntries,
  NetworkIncludeMode include = NetworkIncludeMode.summary,
  int? maxPayloadChars,
  int? maxScanLines,
}) {
  final clampedMaxEntries = _clampInt(maxEntries, 25, 1, 200);
  final clampedMaxPayloadChars = _clampInt(maxPayloadChars, 2048, 64, 16384);
  final clampedMaxScanLines = _clampInt(maxScanLines, 4000, 100, 20000);
  final limits = NetworkDumpLimits(
    maxEntries: clampedMaxEntries,
    maxPayloadChars: clampedMaxPayloadChars,
    maxScanLines: clampedMaxScanLines,
  );
  final allLines = content.split('\n');
  final startIndex = allLines.length > clampedMaxScanLines
      ? allLines.length - clampedMaxScanLines
      : 0;
  final lines = allLines.sublist(startIndex);
  final entries = <NetworkEntry>[];
  for (
    var i = lines.length - 1;
    i >= 0 && entries.length < clampedMaxEntries;
    i -= 1
  ) {
    final trimmed = lines[i].trim();
    if (trimmed.isEmpty) continue;
    final parsed = _parseNetworkLine(
      lines: lines,
      lineIndex: i,
      lineNumber: startIndex + i + 1,
      backend: backend,
      include: include,
      maxPayloadChars: clampedMaxPayloadChars,
    );
    if (parsed == null) continue;
    entries.add(parsed);
  }
  return NetworkDump(
    path: path ?? '<memory>',
    exists: true,
    scannedLines: lines.length,
    matchedLines: entries.length,
    entries: entries,
    include: include,
    limits: limits,
  );
}

/// Merge two dumps, preferring [primary]'s order; secondary entries are
/// appended in order without duplicates (identity = timestamp|method|url|
/// status|raw). Useful when concatenating logs from multiple windows.
NetworkDump mergeNetworkDumps(
  NetworkDump primary,
  NetworkDump secondary, {
  int? maxEntries,
}) {
  final cap = maxEntries ?? primary.limits.maxEntries;
  final seen = <String>{for (final e in primary.entries) _networkEntryKey(e)};
  final merged = <NetworkEntry>[...primary.entries];
  for (final e in secondary.entries) {
    if (merged.length >= cap) break;
    final key = _networkEntryKey(e);
    if (seen.contains(key)) continue;
    seen.add(key);
    merged.add(e);
  }
  return NetworkDump(
    path: primary.path,
    exists: primary.exists,
    scannedLines: primary.scannedLines,
    matchedLines: merged.length,
    entries: merged,
    include: primary.include,
    limits: primary.limits,
  );
}

String _networkEntryKey(NetworkEntry e) =>
    '${e.timestamp ?? ''}|${e.method ?? ''}|${e.url}|${e.status ?? ''}|${e.raw}';

NetworkEntry? _parseNetworkLine({
  required List<String> lines,
  required int lineIndex,
  required int lineNumber,
  required NetworkLogBackend? backend,
  required NetworkIncludeMode include,
  required int maxPayloadChars,
}) {
  final line = lines[lineIndex].trim();
  if (line.isEmpty) return null;

  final maybeJson = _parseEmbeddedJson(line);
  final jsonMethod = _readJsonString(maybeJson, const ['method', 'httpMethod']);
  final jsonUrl = _readJsonString(maybeJson, const ['url', 'requestUrl']);
  final jsonStatus = _readJsonNumber(maybeJson, const [
    'status',
    'statusCode',
    'responseCode',
  ]);

  final methodWithUrlMatch = _methodWithUrlRegex.firstMatch(line);
  final methodFieldMatch = _methodFieldRegex.firstMatch(line);
  final method =
      (jsonMethod ?? methodFieldMatch?.group(1) ?? methodWithUrlMatch?.group(1))
          ?.toUpperCase();

  final urlMatch = _urlRegex.firstMatch(line);
  final url = jsonUrl ?? urlMatch?.group(0);
  if (url == null) return null;

  final inlineStatus = jsonStatus ?? _parseStatusCode(line);
  final hasExplicitNetworkSignal =
      jsonMethod != null ||
      methodFieldMatch?.group(1) != null ||
      methodWithUrlMatch?.group(1) != null ||
      inlineStatus != null ||
      _urlFieldRegex.hasMatch(line) ||
      _headersFieldRegex.hasMatch(line) ||
      _bodyFieldRegex.hasMatch(line);
  if (!hasExplicitNetworkSignal) return null;

  var result = NetworkEntry(
    url: url,
    raw: _truncate(line, maxPayloadChars),
    line: lineNumber,
    method: method,
    status: inlineStatus,
    timestamp: _parseTimestamp(line),
    packetId: _parseAndroidPacketId(line),
    durationMs: _parseAndroidDurationMs(line),
  );

  if (backend == NetworkLogBackend.android) {
    result = _enrichFromAndroidAdjacentLines(result, lines, lineIndex);
  }

  if (include == NetworkIncludeMode.headers ||
      include == NetworkIncludeMode.all) {
    final h = _readHeaders(line, maybeJson);
    if (h != null) {
      result = result.copyWith(headers: _truncate(h, maxPayloadChars));
    }
  }
  if (include == NetworkIncludeMode.body || include == NetworkIncludeMode.all) {
    final req = _readBody(line, maybeJson, const [
      'requestBody',
      'body',
      'payload',
      'request',
    ]);
    final res = _readBody(line, maybeJson, const ['responseBody', 'response']);
    if (req != null) {
      result = result.copyWith(requestBody: _truncate(req, maxPayloadChars));
    }
    if (res != null) {
      result = result.copyWith(responseBody: _truncate(res, maxPayloadChars));
    }
  }

  return result;
}

NetworkEntry _enrichFromAndroidAdjacentLines(
  NetworkEntry result,
  List<String> lines,
  int lineIndex,
) {
  final nearby = _collectNearbyLines(
    lines,
    lineIndex,
    _androidNearbyLineRadius,
  );
  String? packetId = result.packetId;
  if (packetId == null) {
    for (final l in nearby) {
      final pid = _parseAndroidPacketId(l);
      if (pid != null && pid.isNotEmpty) {
        packetId = pid;
        break;
      }
    }
  }
  var out = packetId != null && result.packetId != packetId
      ? result.copyWith(packetId: packetId)
      : result;

  final related = packetId != null
      ? _collectNearbyLines(
          lines,
          lineIndex,
          _androidPacketScanRadius,
        ).where((l) => _parseAndroidPacketId(l) == packetId).toList()
      : nearby;

  if (out.timestamp == null) {
    for (final l in related) {
      final ts = _parseTimestamp(l);
      if (ts != null && ts.isNotEmpty) {
        out = out.copyWith(timestamp: ts);
        break;
      }
    }
  }
  if (out.status == null) {
    for (final l in related) {
      final s = _parseStatusCode(l);
      if (s != null) {
        out = out.copyWith(status: s);
        break;
      }
    }
  }
  if (out.durationMs == null) {
    for (final l in related) {
      final d = _parseAndroidDurationMs(l);
      if (d != null) {
        out = out.copyWith(durationMs: d);
        break;
      }
    }
  }
  return out;
}

List<String> _collectNearbyLines(
  List<String> lines,
  int lineIndex,
  int radius,
) {
  final start = (lineIndex - radius) < 0 ? 0 : lineIndex - radius;
  final end = (lineIndex + radius) >= lines.length
      ? lines.length - 1
      : lineIndex + radius;
  final out = <String>[];
  for (var i = start; i <= end; i += 1) {
    final l = lines[i].trim();
    if (l.isEmpty) continue;
    out.add(l);
  }
  return out;
}

int? _parseStatusCode(String line) {
  for (final pattern in _statusPatterns) {
    final m = pattern.firstMatch(line);
    if (m == null) continue;
    final value = int.tryParse(m.group(1) ?? '');
    if (value != null) return value;
  }
  return null;
}

String? _parseTimestamp(String line) {
  final iso = _isoTimestampRegex.firstMatch(line);
  if (iso != null) return iso.group(0);
  final android = _androidTimestampRegex.firstMatch(line);
  return android?.group(0);
}

String? _parseAndroidPacketId(String line) =>
    _androidPacketIdRegex.firstMatch(line)?.group(1);

int? _parseAndroidDurationMs(String line) {
  final m = _androidDurationRegex.firstMatch(line);
  if (m == null) return null;
  return int.tryParse(m.group(1) ?? '');
}

Map<String, Object?>? _parseEmbeddedJson(String line) {
  final start = line.indexOf('{');
  if (start < 0) return null;
  final end = line.lastIndexOf('}');
  if (end <= start) return null;
  final candidate = line.substring(start, end + 1);
  try {
    final parsed = jsonDecode(candidate);
    return parsed is Map ? parsed.cast<String, Object?>() : null;
  } catch (_) {
    return null;
  }
}

String? _readJsonString(Map<String, Object?>? value, List<String> keys) {
  if (value == null) return null;
  for (final key in keys) {
    final next = value[key];
    if (next is String && next.trim().isNotEmpty) return next.trim();
  }
  return null;
}

int? _readJsonNumber(Map<String, Object?>? value, List<String> keys) {
  if (value == null) return null;
  for (final key in keys) {
    final next = value[key];
    if (next is int) return next;
    if (next is num) {
      final i = next.toInt();
      if (i.toDouble() == next.toDouble()) return i;
    }
    if (next is String && RegExp(r'^\d{3}$').hasMatch(next.trim())) {
      final i = int.tryParse(next.trim());
      if (i != null) return i;
    }
  }
  return null;
}

String? _readHeaders(String line, Map<String, Object?>? json) {
  if (json != null) {
    final headers =
        json['headers'] ?? json['requestHeaders'] ?? json['responseHeaders'];
    if (headers != null) return _stringifyValue(headers);
  }
  final match = _headersJsonRegex.firstMatch(line);
  final g = match?.group(1)?.trim();
  if (g != null && g.isNotEmpty) return g;
  return null;
}

String? _readBody(
  String line,
  Map<String, Object?>? json,
  List<String> jsonKeys,
) {
  if (json != null) {
    for (final key in jsonKeys) {
      if (json.containsKey(key) && json[key] != null) {
        return _stringifyValue(json[key]);
      }
    }
  }
  for (final key in jsonKeys) {
    final escaped = RegExp.escape(key);
    final regex = RegExp(
      '\\b$escaped'
      r'''["'=: ]+(.+)$''',
      caseSensitive: false,
    );
    final m = regex.firstMatch(line);
    final g = m?.group(1)?.trim();
    if (g != null && g.isNotEmpty) return g;
  }
  return null;
}

String _stringifyValue(Object? value) {
  if (value is String) return value;
  try {
    return jsonEncode(value);
  } catch (_) {
    return value.toString();
  }
}

String _truncate(String value, int maxChars) {
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars)}...<truncated>';
}
