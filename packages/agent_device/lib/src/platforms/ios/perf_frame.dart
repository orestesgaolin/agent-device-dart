// Port of agent-device/src/platforms/ios/perf-frame.ts
//
// Parses xctrace Animation Hitches output to produce an [AppleFramePerfSample]
// describing frame-drop health for an iOS app process.
library;

import 'package:xml/xml.dart';

import '../perf_utils.dart';
import 'perf_xml.dart';

const int _maxWorstWindows = 3;
const int _jankWindowGapNs = 500000000;

/// Method identifier for Apple frame-health sampling.
const String appleFrameSampleMethod = 'xctrace-animation-hitches';

/// Human-readable description of the sampling method.
const String appleFrameSampleDescription =
    'Rendered-frame hitch health from xctrace Animation Hitches on connected '
    'iOS devices. Dropped frames are counted from native hitch rows for the '
    'attached app process, with total frames from the same trace frame-lifetime table.';

/// A cluster of consecutive dropped frames forming a jank window.
class AppleFrameDropWindow {
  final int startOffsetMs;
  final int endOffsetMs;
  final String? startAt;
  final String? endAt;
  final int missedDeadlineFrameCount;
  final double worstFrameMs;

  const AppleFrameDropWindow({
    required this.startOffsetMs,
    required this.endOffsetMs,
    this.startAt,
    this.endAt,
    required this.missedDeadlineFrameCount,
    required this.worstFrameMs,
  });

  Map<String, Object?> toJson() => {
    'startOffsetMs': startOffsetMs,
    'endOffsetMs': endOffsetMs,
    if (startAt != null) 'startAt': startAt,
    if (endAt != null) 'endAt': endAt,
    'missedDeadlineFrameCount': missedDeadlineFrameCount,
    'worstFrameMs': worstFrameMs,
  };
}

/// Aggregate frame-drop metrics for an iOS app process sampled via
/// `xctrace record --template 'Animation Hitches'`.
class AppleFramePerfSample {
  final double droppedFramePercent;
  final int droppedFrameCount;
  final int totalFrameCount;
  final int sampleWindowMs;
  final String windowStartedAt;
  final String windowEndedAt;
  final String measuredAt;
  final String method;
  final List<String> matchedProcesses;
  final double? frameDeadlineMs;
  final double? refreshRateHz;
  final List<AppleFrameDropWindow>? worstWindows;

  const AppleFramePerfSample({
    required this.droppedFramePercent,
    required this.droppedFrameCount,
    required this.totalFrameCount,
    required this.sampleWindowMs,
    required this.windowStartedAt,
    required this.windowEndedAt,
    required this.measuredAt,
    required this.method,
    required this.matchedProcesses,
    this.frameDeadlineMs,
    this.refreshRateHz,
    this.worstWindows,
  });
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

class _HitchRow {
  final int startNs;
  final int durationNs;
  final int? pid;
  final String? processName;

  const _HitchRow({
    required this.startNs,
    required this.durationNs,
    this.pid,
    this.processName,
  });
}

class _HitchSchemaIndexes {
  final int start;
  final int duration;
  final int process;
  final int isSystem;

  const _HitchSchemaIndexes({
    required this.start,
    required this.duration,
    required this.process,
    required this.isSystem,
  });
}

// Reference cache entry: a resolved numeric value and/or process info.
typedef _XmlRef = ({double? numberValue, ({int? pid, String? name})? process});

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parse xctrace Animation Hitches XML output into an [AppleFramePerfSample].
///
/// [hitchesXml] — exported `hitches` schema table XML.
/// [frameLifetimesXml] — exported `hitches-frame-lifetimes` schema table XML.
/// [displayInfoXml] — optional exported `device-display-info` schema table XML.
/// [processIds] / [processNames] — PIDs and executable names to filter hitches by.
/// [windowStartedAt] / [windowEndedAt] — ISO-8601 timestamps bounding the recording.
/// [measuredAt] — ISO-8601 timestamp at which the sample is considered captured.
AppleFramePerfSample parseAppleFramePerfSample({
  required String hitchesXml,
  required String frameLifetimesXml,
  String? displayInfoXml,
  required List<int> processIds,
  required List<String> processNames,
  required String windowStartedAt,
  required String windowEndedAt,
  required String measuredAt,
}) {
  final totalFrameCount = _parseAppleFrameLifetimeCount(frameLifetimesXml);
  final refreshRateHz = _parseAppleDisplayRefreshRate(displayInfoXml);
  final allHitches = _parseAppleHitchRows(hitchesXml);
  final hitches = allHitches
      .where((r) => _matchesProcess(r, processIds, processNames))
      .toList();
  final droppedFrameCount = hitches.length;

  final startMs = DateTime.tryParse(windowStartedAt)?.millisecondsSinceEpoch ?? 0;
  final endMs = DateTime.tryParse(windowEndedAt)?.millisecondsSinceEpoch ?? 0;
  final sampleWindowMs = (endMs - startMs).clamp(0, double.maxFinite.toInt());

  final worstWindows = _buildWorstWindows(hitches, startMs);

  return AppleFramePerfSample(
    droppedFramePercent:
        totalFrameCount > 0
            ? roundPercent((droppedFrameCount / totalFrameCount) * 100)
            : 0,
    droppedFrameCount: droppedFrameCount,
    totalFrameCount: totalFrameCount,
    sampleWindowMs: sampleWindowMs,
    windowStartedAt: windowStartedAt,
    windowEndedAt: windowEndedAt,
    measuredAt: measuredAt,
    method: appleFrameSampleMethod,
    matchedProcesses: _uniqueStrings(
      hitches
          .map((r) => r.processName)
          .where((n) => n != null && n.isNotEmpty)
          .cast<String>()
          .toList(),
    ),
    frameDeadlineMs:
        refreshRateHz == null ? null : roundOneDecimal(1000 / refreshRateHz),
    refreshRateHz: refreshRateHz,
    worstWindows: worstWindows.isNotEmpty ? worstWindows : null,
  );
}

// ---------------------------------------------------------------------------
// Frame lifetime count
// ---------------------------------------------------------------------------

int _parseAppleFrameLifetimeCount(String xml) {
  return _parseRows(xml, 'hitches-frame-lifetimes').length;
}

// ---------------------------------------------------------------------------
// Display refresh rate
// ---------------------------------------------------------------------------

double? _parseAppleDisplayRefreshRate(String? xml) {
  if (xml == null || xml.isEmpty) return null;
  final (rows: rows, schema: schema) = _parseTable(xml, 'device-display-info');
  final refreshIndex = schema.indexOf('max-refresh-rate');
  if (refreshIndex < 0) return null;
  final references = <String, _XmlRef>{};
  for (final row in rows) {
    _rememberReferences(row.childElements.toList(), references);
    final cells = row.childElements.toList();
    if (refreshIndex >= cells.length) continue;
    final rate = resolveXmlNumber(cells[refreshIndex], _numberOnlyRefs(references));
    if (rate != null && rate > 0) return rate;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Hitch row parsing
// ---------------------------------------------------------------------------

List<_HitchRow> _parseAppleHitchRows(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException {
    return const [];
  }
  final indexes = _readHitchSchemaIndexes(doc);
  if (indexes == null) return const [];
  final references = <String, _XmlRef>{};
  return findAllXmlElements(
        doc.children,
        (el) => el.localName == 'row',
      )
      .map((row) => _readHitchRow(row, indexes, references))
      .whereType<_HitchRow>()
      .toList();
}

_HitchSchemaIndexes? _readHitchSchemaIndexes(XmlDocument doc) {
  final columns = readSchemaColumns(doc, 'hitches');
  final start = columns.indexOf('start');
  final duration = columns.indexOf('duration');
  final process = columns.indexOf('process');
  final isSystem = columns.indexOf('is-system');
  if (start < 0 || duration < 0 || process < 0 || isSystem < 0) return null;
  return _HitchSchemaIndexes(
    start: start,
    duration: duration,
    process: process,
    isSystem: isSystem,
  );
}

_HitchRow? _readHitchRow(
  XmlElement row,
  _HitchSchemaIndexes indexes,
  Map<String, _XmlRef> references,
) {
  final cells = row.childElements.toList();
  _rememberReferences(cells, references);
  // Skip system hitches (is-system == 1).
  final isSystemEl = indexes.isSystem < cells.length ? cells[indexes.isSystem] : null;
  if (_resolveXmlBoolean(isSystemEl, _numberOnlyRefs(references)) == true) return null;

  final startEl = indexes.start < cells.length ? cells[indexes.start] : null;
  final durationEl = indexes.duration < cells.length ? cells[indexes.duration] : null;
  final startNsRaw = resolveXmlNumber(startEl, _numberOnlyRefs(references));
  final durationNsRaw = resolveXmlNumber(durationEl, _numberOnlyRefs(references));
  if (startNsRaw == null || durationNsRaw == null) return null;

  final processEl = indexes.process < cells.length ? cells[indexes.process] : null;
  final proc = _resolveXmlProcess(processEl, references);

  return _HitchRow(
    startNs: startNsRaw.toInt(),
    durationNs: durationNsRaw.toInt(),
    pid: proc?.pid,
    processName: proc?.name,
  );
}

bool _matchesProcess(
  _HitchRow row,
  List<int> processIds,
  List<String> processNames,
) {
  if (row.pid != null && processIds.contains(row.pid)) return true;
  if (row.processName == null) return false;
  return processNames.contains(row.processName);
}

// ---------------------------------------------------------------------------
// Worst-window clustering
// ---------------------------------------------------------------------------

List<AppleFrameDropWindow> _buildWorstWindows(
  List<_HitchRow> hitches,
  int windowStartedAtMs,
) {
  if (hitches.isEmpty) return const [];
  final sorted = List<_HitchRow>.of(hitches)
    ..sort((a, b) => a.startNs.compareTo(b.startNs));

  final windows = <List<_HitchRow>>[];
  var current = <_HitchRow>[];
  for (final hitch in sorted) {
    final previous = current.isNotEmpty ? current.last : null;
    if (previous == null ||
        hitch.startNs - (previous.startNs + previous.durationNs) <=
            _jankWindowGapNs) {
      current.add(hitch);
    } else {
      windows.add(current);
      current = [hitch];
    }
  }
  if (current.isNotEmpty) windows.add(current);

  final built =
      windows.map((rows) => _buildWorstWindow(rows, windowStartedAtMs)).toList();
  // Sort by missedDeadlineFrameCount desc, then worstFrameMs desc — take top N.
  built.sort(
    (a, b) =>
        b.missedDeadlineFrameCount != a.missedDeadlineFrameCount
            ? b.missedDeadlineFrameCount.compareTo(a.missedDeadlineFrameCount)
            : b.worstFrameMs.compareTo(a.worstFrameMs),
  );
  final top = built.take(_maxWorstWindows).toList();
  // Re-sort by start offset ascending for output ordering.
  top.sort((a, b) => a.startOffsetMs.compareTo(b.startOffsetMs));
  return top;
}

AppleFrameDropWindow _buildWorstWindow(
  List<_HitchRow> hitches,
  int windowStartedAtMs,
) {
  final startNs = hitches.map((h) => h.startNs).reduce((a, b) => a < b ? a : b);
  final endNs = hitches
      .map((h) => h.startNs + h.durationNs)
      .reduce((a, b) => a > b ? a : b);
  final startOffsetMs = (startNs / 1000000).round();
  final rawEndOffsetMs = (endNs / 1000000).round();
  final endOffsetMs =
      rawEndOffsetMs < startOffsetMs ? startOffsetMs : rawEndOffsetMs;
  final worstDurationNs =
      hitches.map((h) => h.durationNs).reduce((a, b) => a > b ? a : b);
  final clampedStart = startOffsetMs < 0 ? 0 : startOffsetMs;
  return AppleFrameDropWindow(
    startOffsetMs: clampedStart,
    endOffsetMs: endOffsetMs,
    startAt: DateTime.fromMillisecondsSinceEpoch(
      windowStartedAtMs + clampedStart,
      isUtc: true,
    ).toIso8601String(),
    endAt: DateTime.fromMillisecondsSinceEpoch(
      windowStartedAtMs + endOffsetMs,
      isUtc: true,
    ).toIso8601String(),
    missedDeadlineFrameCount: hitches.length,
    worstFrameMs: roundOneDecimal(worstDurationNs / 1000000),
  );
}

// ---------------------------------------------------------------------------
// XML reference / process resolution helpers (frame-perf specific)
// ---------------------------------------------------------------------------

/// Walk [elements] depth-first and cache any element with an `id` attribute.
void _rememberReferences(
  List<XmlElement> elements,
  Map<String, _XmlRef> references,
) {
  for (final el in elements) {
    _rememberReferences(el.childElements.toList(), references);
    final id = el.getAttribute('id');
    if (id == null) continue;
    references[id] = (
      numberValue: parseDirectXmlNumber(el),
      process: _readDirectProcess(el),
    );
  }
}

/// Project a full reference map down to just the numeric-value subset
/// required by [resolveXmlNumber].
Map<String, ({double? numberValue})> _numberOnlyRefs(
  Map<String, _XmlRef> refs,
) {
  // Build a thin wrapper — values are already the right shape.
  return refs.map((k, v) => MapEntry(k, (numberValue: v.numberValue)));
}

bool? _resolveXmlBoolean(
  XmlElement? element,
  Map<String, ({double? numberValue})> references,
) {
  final value = resolveXmlNumber(element, references);
  if (value == null) return null;
  return value != 0;
}

({int? pid, String? name})? _resolveXmlProcess(
  XmlElement? element,
  Map<String, _XmlRef> references,
) {
  if (element == null) return null;
  final ref = element.getAttribute('ref');
  if (ref != null) return references[ref]?.process;
  return _readDirectProcess(element);
}

({int? pid, String? name})? _readDirectProcess(XmlElement? element) {
  if (element == null) return null;
  if (element.childElements.any((c) => c.localName == 'sentinel')) return null;
  final pidEl = findFirstXmlElement(
    element.children,
    (c) => c.localName == 'pid',
  );
  final pidRaw = parseDirectXmlNumber(pidEl);
  final pid = pidRaw?.toInt();
  // fmt attribute has the form "AppName (1234)" — strip the trailing PID.
  final fmt = (element.getAttribute('fmt') ?? '').trim();
  final name =
      fmt.isEmpty ? '' : fmt.replaceFirst(RegExp(r'\s+\(\d+\)$'), '').trim();
  if (pid == null && name.isEmpty) return null;
  return (pid: pid, name: name.isNotEmpty ? name : null);
}

// ---------------------------------------------------------------------------
// XML table parsing helpers
// ---------------------------------------------------------------------------

List<XmlElement> _parseRows(String xml, String schemaName) {
  return _parseTable(xml, schemaName).rows;
}

({List<XmlElement> rows, List<String> schema}) _parseTable(
  String xml,
  String schemaName,
) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException {
    return (rows: const [], schema: const []);
  }
  final schema = readSchemaColumns(doc, schemaName);
  if (schema.isEmpty) return (rows: const [], schema: const []);
  final rows = findAllXmlElements(doc.children, (el) => el.localName == 'row');
  return (rows: rows, schema: schema);
}

// ---------------------------------------------------------------------------
// Miscellaneous
// ---------------------------------------------------------------------------

List<String> _uniqueStrings(List<String> values) =>
    values.toSet().toList(growable: false);
