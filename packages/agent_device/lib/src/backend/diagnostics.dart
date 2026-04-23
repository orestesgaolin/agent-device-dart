// Port of agent-device/src/backend.ts
library;

// ============================================================================
// Logging
// ============================================================================

/// A single log entry.
class BackendLogEntry {
  final String? timestamp;
  final String? level;
  final String message;
  final String? source;
  final Map<String, Object?>? metadata;

  const BackendLogEntry({
    this.timestamp,
    this.level,
    required this.message,
    this.source,
    this.metadata,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    if (timestamp != null) 'timestamp': timestamp,
    if (level != null) 'level': level,
    'message': message,
    if (source != null) 'source': source,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Options for reading logs.
class BackendReadLogsOptions {
  final String? cursor;
  final int? limit;
  final String? since;
  final String? until;
  final List<String>? levels;
  final String? search;
  final String? source;

  const BackendReadLogsOptions({
    this.cursor,
    this.limit,
    this.since,
    this.until,
    this.levels,
    this.search,
    this.source,
  });
}

/// Result of reading logs.
class BackendReadLogsResult {
  final List<BackendLogEntry> entries;
  final String? nextCursor;
  final BackendDiagnosticsTimeWindow? timeWindow;
  final String? backend;
  final bool? redacted;
  final List<String>? notes;

  const BackendReadLogsResult({
    required this.entries,
    this.nextCursor,
    this.timeWindow,
    this.backend,
    this.redacted,
    this.notes,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'entries': entries.map((e) => e.toJson()).toList(),
    if (nextCursor != null) 'nextCursor': nextCursor,
    if (timeWindow != null) 'timeWindow': timeWindow!.toJson(),
    if (backend != null) 'backend': backend,
    if (redacted != null) 'redacted': redacted,
    if (notes != null) 'notes': notes,
  };
}

// ============================================================================
// Network
// ============================================================================

/// Network activity detail level.
enum BackendNetworkIncludeMode {
  summary('summary'),
  headers('headers'),
  body('body'),
  all('all');

  final String value;

  const BackendNetworkIncludeMode(this.value);

  static BackendNetworkIncludeMode? fromString(String? value) {
    return switch (value) {
      'summary' => BackendNetworkIncludeMode.summary,
      'headers' => BackendNetworkIncludeMode.headers,
      'body' => BackendNetworkIncludeMode.body,
      'all' => BackendNetworkIncludeMode.all,
      _ => null,
    };
  }

  @override
  String toString() => value;
}

/// A single network request/response entry.
class BackendNetworkEntry {
  final String? timestamp;
  final String? method;
  final String? url;
  final int? status;
  final int? durationMs;
  final Map<String, String>? requestHeaders;
  final Map<String, String>? responseHeaders;
  final String? requestBody;
  final String? responseBody;
  final Map<String, Object?>? metadata;

  const BackendNetworkEntry({
    this.timestamp,
    this.method,
    this.url,
    this.status,
    this.durationMs,
    this.requestHeaders,
    this.responseHeaders,
    this.requestBody,
    this.responseBody,
    this.metadata,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    if (timestamp != null) 'timestamp': timestamp,
    if (method != null) 'method': method,
    if (url != null) 'url': url,
    if (status != null) 'status': status,
    if (durationMs != null) 'durationMs': durationMs,
    if (requestHeaders != null) 'requestHeaders': requestHeaders,
    if (responseHeaders != null) 'responseHeaders': responseHeaders,
    if (requestBody != null) 'requestBody': requestBody,
    if (responseBody != null) 'responseBody': responseBody,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Options for dumping network activity.
class BackendDumpNetworkOptions {
  final String? cursor;
  final int? limit;
  final String? since;
  final String? until;
  final BackendNetworkIncludeMode? include;

  const BackendDumpNetworkOptions({
    this.cursor,
    this.limit,
    this.since,
    this.until,
    this.include,
  });
}

/// Result of dumping network activity.
class BackendDumpNetworkResult {
  final List<BackendNetworkEntry> entries;
  final String? nextCursor;
  final BackendDiagnosticsTimeWindow? timeWindow;
  final String? backend;
  final bool? redacted;
  final List<String>? notes;

  const BackendDumpNetworkResult({
    required this.entries,
    this.nextCursor,
    this.timeWindow,
    this.backend,
    this.redacted,
    this.notes,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'entries': entries.map((e) => e.toJson()).toList(),
    if (nextCursor != null) 'nextCursor': nextCursor,
    if (timeWindow != null) 'timeWindow': timeWindow!.toJson(),
    if (backend != null) 'backend': backend,
    if (redacted != null) 'redacted': redacted,
    if (notes != null) 'notes': notes,
  };
}

// ============================================================================
// Performance Metrics
// ============================================================================

/// A single performance metric.
class BackendPerfMetric {
  final String name;
  final double? value;
  final String? unit;
  final String? status;
  final String? message;
  final Map<String, Object?>? metadata;

  const BackendPerfMetric({
    required this.name,
    this.value,
    this.unit,
    this.status,
    this.message,
    this.metadata,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (value != null) 'value': value,
    if (unit != null) 'unit': unit,
    if (status != null) 'status': status,
    if (message != null) 'message': message,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Options for measuring performance.
class BackendMeasurePerfOptions {
  final String? since;
  final String? until;
  final int? sampleMs;
  final List<String>? metrics;

  const BackendMeasurePerfOptions({
    this.since,
    this.until,
    this.sampleMs,
    this.metrics,
  });
}

/// Result of measuring performance.
class BackendMeasurePerfResult {
  final List<BackendPerfMetric> metrics;
  final String? startedAt;
  final String? endedAt;
  final String? backend;
  final bool? redacted;
  final List<String>? notes;

  const BackendMeasurePerfResult({
    required this.metrics,
    this.startedAt,
    this.endedAt,
    this.backend,
    this.redacted,
    this.notes,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'metrics': metrics.map((m) => m.toJson()).toList(),
    if (startedAt != null) 'startedAt': startedAt,
    if (endedAt != null) 'endedAt': endedAt,
    if (backend != null) 'backend': backend,
    if (redacted != null) 'redacted': redacted,
    if (notes != null) 'notes': notes,
  };
}

// ============================================================================
// Common Time Window
// ============================================================================

/// A time window for diagnostic queries.
class BackendDiagnosticsTimeWindow {
  final String? since;
  final String? until;

  const BackendDiagnosticsTimeWindow({this.since, this.until});

  Map<String, Object?> toJson() => <String, Object?>{
    if (since != null) 'since': since,
    if (until != null) 'until': until,
  };
}
