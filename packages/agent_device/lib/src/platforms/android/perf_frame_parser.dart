// Port of agent-device/src/platforms/android/perf-frame-parser.ts

import '../../utils/errors.dart';
import '../perf_utils.dart' show roundPercent;
import 'perf_frame_analysis.dart';

export 'perf_frame_analysis.dart' show AndroidFrameDropWindow;

const String androidFrameSampleMethod = 'adb-shell-dumpsys-gfxinfo-framestats';
const String androidFrameSampleDescription =
    'Rendered-frame health from the current adb shell dumpsys gfxinfo <package> framestats window. '
    'Dropped frames use Android gfxinfo janky-frame/frame-deadline data when available; '
    'this is not video recording FPS.';

class _AndroidFrameSummary {
  final double droppedFramePercent;
  final int droppedFrameCount;
  final int totalFrameCount;
  final int? sampleWindowMs;
  final int? uptimeMs;
  final int? statsSinceNs;

  const _AndroidFrameSummary({
    required this.droppedFramePercent,
    required this.droppedFrameCount,
    required this.totalFrameCount,
    this.sampleWindowMs,
    this.uptimeMs,
    this.statsSinceNs,
  });
}

class _AndroidFrameCounts {
  final double droppedFramePercent;
  final int droppedFrameCount;
  final int totalFrameCount;

  const _AndroidFrameCounts({
    required this.droppedFramePercent,
    required this.droppedFrameCount,
    required this.totalFrameCount,
  });
}

class _AndroidFrameTiming {
  final int? sampleWindowMs;
  final int? windowStartNs;
  final String? windowStartedAt;
  final String? windowEndedAt;
  final String? timestampSource;

  const _AndroidFrameTiming({
    this.sampleWindowMs,
    this.windowStartNs,
    this.windowStartedAt,
    this.windowEndedAt,
    this.timestampSource,
  });
}

/// Android frame performance sample from `adb shell dumpsys gfxinfo framestats`.
class AndroidFramePerfSample {
  final double droppedFramePercent;
  final int droppedFrameCount;
  final int totalFrameCount;
  final int? sampleWindowMs;
  final double? frameDeadlineMs;
  final double? refreshRateHz;
  final String? windowStartedAt;
  final String? windowEndedAt;
  /// Always `'estimated-from-device-uptime'` when set.
  final String? timestampSource;
  final String measuredAt;
  final String method;
  final String source;
  final List<AndroidFrameDropWindow>? worstWindows;

  const AndroidFramePerfSample({
    required this.droppedFramePercent,
    required this.droppedFrameCount,
    required this.totalFrameCount,
    this.sampleWindowMs,
    this.frameDeadlineMs,
    this.refreshRateHz,
    this.windowStartedAt,
    this.windowEndedAt,
    this.timestampSource,
    required this.measuredAt,
    required this.method,
    required this.source,
    this.worstWindows,
  });
}

/// Parses [stdout] from `adb shell dumpsys gfxinfo <package> framestats` into
/// an [AndroidFramePerfSample].
AndroidFramePerfSample parseAndroidFramePerfSample(
  String stdout,
  String packageName,
  String measuredAt,
) {
  _assertAndroidGfxInfoProcessFound(stdout, packageName);
  final summary = _parseAndroidFrameSummary(stdout);
  final frames = _parseAndroidFrameStatsRows(stdout);
  final frameDeadlineNs = _readAndroidFrameDeadlineNs(
    frames,
    summary,
    packageName,
  );
  final measuredAtMs = DateTime.parse(measuredAt).millisecondsSinceEpoch;
  final timing = _buildAndroidFrameTiming(
    frames: frames,
    measuredAtMs: measuredAtMs,
    summary: summary,
  );
  final droppedFrames = selectDroppedFrameRows(
    frames: frames,
    frameDeadlineNs: frameDeadlineNs,
    summaryDroppedFrameCount: summary?.droppedFrameCount,
  );
  final sampleWindowMs =
      summary?.sampleWindowMs ?? timing.sampleWindowMs ?? _computeFrameWindowMs(frames);
  final counts = _buildAndroidFrameCounts(summary, frames, droppedFrames);
  final worstWindows = _buildAndroidWorstWindows(
    droppedFrames: droppedFrames,
    timing: timing,
    measuredAtMs: measuredAtMs,
    summary: summary,
  );

  return AndroidFramePerfSample(
    droppedFramePercent: counts.droppedFramePercent,
    droppedFrameCount: counts.droppedFrameCount,
    totalFrameCount: counts.totalFrameCount,
    sampleWindowMs: sampleWindowMs,
    frameDeadlineMs: _frameDeadlineMs(frameDeadlineNs),
    refreshRateHz: _refreshRateHz(frameDeadlineNs),
    windowStartedAt: timing.windowStartedAt,
    windowEndedAt: timing.windowEndedAt,
    timestampSource: timing.timestampSource,
    measuredAt: measuredAt,
    method: androidFrameSampleMethod,
    source: summary != null ? 'android-gfxinfo-summary' : 'framestats-rows',
    worstWindows:
        (worstWindows != null && worstWindows.isNotEmpty) ? worstWindows : null,
  );
}

void _assertAndroidGfxInfoProcessFound(
  String stdout,
  String packageName,
) {
  if (!RegExp(r'no process found for:', caseSensitive: false).hasMatch(stdout)) {
    return;
  }
  throw AppError(
    AppErrorCodes.commandFailed,
    'Android gfxinfo did not find a running process for $packageName',
    details: {
      'metric': 'fps',
      'package': packageName,
      'hint':
          'Run open <app> for this session again to ensure the Android app is '
          'active, then retry perf after the interaction you want to inspect.',
    },
  );
}

Never _throwFrameParseError(String packageName) {
  throw AppError(
    AppErrorCodes.commandFailed,
    'Failed to parse Android framestats output for $packageName',
    details: {
      'metric': 'fps',
      'package': packageName,
      'hint':
          'Retry perf after exercising the app screen. If the problem persists, '
          'capture adb shell dumpsys gfxinfo <package> framestats output for debugging.',
    },
  );
}

int? _readAndroidFrameDeadlineNs(
  List<AndroidFrameStatsRow> frames,
  _AndroidFrameSummary? summary,
  String packageName,
) {
  final frameDeadlineNs = deriveFrameDeadlineNs(frames);
  if (summary == null && frames.isEmpty) {
    _throwFrameParseError(packageName);
  }
  if (summary != null || frameDeadlineNs != null) return frameDeadlineNs;
  throw AppError(
    AppErrorCodes.commandFailed,
    'Failed to infer Android frame deadline from framestats output for $packageName',
    details: {
      'metric': 'fps',
      'package': packageName,
      'hint':
          'Retry perf after a longer interaction window so consecutive Android '
          'frame timestamps are available.',
    },
  );
}

_AndroidFrameCounts _buildAndroidFrameCounts(
  _AndroidFrameSummary? summary,
  List<AndroidFrameStatsRow> frames,
  List<AndroidFrameStatsRow> droppedFrames,
) {
  final totalFrameCount = summary?.totalFrameCount ?? frames.length;
  final droppedFrameCount = summary?.droppedFrameCount ?? droppedFrames.length;
  final double droppedFramePercent;
  if (summary != null) {
    droppedFramePercent = summary.droppedFramePercent;
  } else if (totalFrameCount > 0) {
    droppedFramePercent =
        roundPercent((droppedFrameCount / totalFrameCount) * 100);
  } else {
    droppedFramePercent = 0;
  }
  return _AndroidFrameCounts(
    totalFrameCount: totalFrameCount,
    droppedFrameCount: droppedFrameCount,
    droppedFramePercent: droppedFramePercent,
  );
}

double? _frameDeadlineMs(int? frameDeadlineNs) {
  if (frameDeadlineNs == null) return null;
  return roundOneDecimal(frameDeadlineNs / 1000000);
}

double? _refreshRateHz(int? frameDeadlineNs) {
  if (frameDeadlineNs == null) return null;
  return roundOneDecimal(1000000000 / frameDeadlineNs);
}

List<AndroidFrameDropWindow>? _buildAndroidWorstWindows({
  required List<AndroidFrameStatsRow> droppedFrames,
  required _AndroidFrameTiming timing,
  required int measuredAtMs,
  _AndroidFrameSummary? summary,
}) {
  if (droppedFrames.isEmpty) return null;
  final worstWindows = buildWorstFrameDropWindows(
    frames: droppedFrames,
    windowStartNs: timing.windowStartNs,
    measuredAtMs: measuredAtMs,
    uptimeMs: summary?.uptimeMs,
  );
  return worstWindows.isNotEmpty ? worstWindows : null;
}

List<AndroidFrameStatsRow> _parseAndroidFrameStatsRows(String text) {
  final rows = <AndroidFrameStatsRow>[];
  Map<String, int>? columnIndex;

  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line == '---PROFILEDATA---') continue;

    final cells = line.split(',').map((c) => c.trim()).toList();
    if (_isFrameStatsHeader(cells)) {
      columnIndex = {
        for (int i = 0; i < cells.length; i++) cells[i]: i,
      };
      continue;
    }
    final row = _parseFrameStatsDataRow(cells, columnIndex);
    if (row != null) rows.add(row);
  }

  rows.sort((a, b) => a.intendedVsyncNs.compareTo(b.intendedVsyncNs));
  return rows;
}

bool _isFrameStatsHeader(List<String> cells) {
  return cells.contains('IntendedVsync') && cells.contains('FrameCompleted');
}

AndroidFrameStatsRow? _parseFrameStatsDataRow(
  List<String> cells,
  Map<String, int>? columnIndex,
) {
  if (columnIndex == null || cells.length < columnIndex.length) return null;
  final flags = _readFrameStatsInt(cells, columnIndex, 'Flags');
  final intendedVsyncNs = _readFrameStatsInt(cells, columnIndex, 'IntendedVsync');
  final frameCompletedNs = _readFrameStatsInt(cells, columnIndex, 'FrameCompleted');
  if (flags != 0 ||
      intendedVsyncNs == null ||
      frameCompletedNs == null ||
      intendedVsyncNs <= 0 ||
      frameCompletedNs <= intendedVsyncNs) {
    return null;
  }
  return AndroidFrameStatsRow(
    intendedVsyncNs: intendedVsyncNs,
    frameCompletedNs: frameCompletedNs,
    durationNs: frameCompletedNs - intendedVsyncNs,
  );
}

/// Reads a column value as an int. Returns null when the column is missing or
/// the value is not a valid finite number. Returns 0 for the Flags column when
/// the parsed value is 0 (zero is a valid flag value).
int? _readFrameStatsInt(
  List<String> cells,
  Map<String, int> columnIndex,
  String column,
) {
  final index = columnIndex[column];
  if (index == null) return null;
  final value = double.tryParse(cells[index]);
  if (value == null || !value.isFinite) return null;
  return value.toInt();
}

_AndroidFrameSummary? _parseAndroidFrameSummary(String text) {
  final summaryText = text.split(RegExp(r'\nProfile data in ms:\n', caseSensitive: false)).first;
  final totalFrameCount = _matchSummaryInteger(summaryText, 'Total frames rendered');
  final jankyFrameMatch = RegExp(
    r'^\s*Janky frames:\s*([0-9][0-9,]*)\s*\(([0-9.]+)%\)',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(summaryText);
  if (totalFrameCount == null || jankyFrameMatch == null) return null;

  final droppedFrameCount = _parseNumericToken(jankyFrameMatch.group(1));
  final droppedFramePercent = double.tryParse(jankyFrameMatch.group(2) ?? '');
  if (droppedFrameCount == null ||
      droppedFramePercent == null ||
      !droppedFramePercent.isFinite ||
      totalFrameCount < 0) {
    return null;
  }

  final uptimeMs = _matchSummaryInteger(summaryText, 'Uptime');
  final statsSinceNs = _matchSummaryInteger(summaryText, 'Stats since');
  return _AndroidFrameSummary(
    droppedFramePercent: roundPercent(droppedFramePercent),
    droppedFrameCount: droppedFrameCount,
    totalFrameCount: totalFrameCount,
    sampleWindowMs: _parseAndroidFrameSummaryWindowMs(
      uptimeMs: uptimeMs,
      statsSinceNs: statsSinceNs,
    ),
    uptimeMs: uptimeMs,
    statsSinceNs: statsSinceNs,
  );
}

int? _parseAndroidFrameSummaryWindowMs({
  int? uptimeMs,
  int? statsSinceNs,
}) {
  if (uptimeMs == null || statsSinceNs == null) return null;
  final windowMs = uptimeMs - (statsSinceNs / 1000000).round();
  return windowMs >= 0 ? windowMs : null;
}

_AndroidFrameTiming _buildAndroidFrameTiming({
  required List<AndroidFrameStatsRow> frames,
  required int measuredAtMs,
  _AndroidFrameSummary? summary,
}) {
  final bounds = _computeFrameBounds(frames);
  final summaryStartNs = summary?.statsSinceNs;
  final windowStartNs = summaryStartNs ?? bounds.firstFrameNs;
  final rawSampleWindowMs = _computeWindowDurationMs(
    windowStartNs,
    bounds.lastFrameNs,
  );
  final sampleWindowMs = summary?.sampleWindowMs ?? rawSampleWindowMs;

  if (summary?.uptimeMs == null || windowStartNs == null) {
    return _AndroidFrameTiming(
      sampleWindowMs: sampleWindowMs,
      windowStartNs: windowStartNs,
    );
  }

  final deviceBootWallClockMs = measuredAtMs - summary!.uptimeMs!;
  // Summary windows extend to the dumpsys read. The retained raw rows can end earlier.
  return _AndroidFrameTiming(
    sampleWindowMs: sampleWindowMs,
    windowStartNs: windowStartNs,
    windowStartedAt: DateTime.fromMillisecondsSinceEpoch(
      deviceBootWallClockMs + (windowStartNs / 1000000).round(),
      isUtc: true,
    ).toIso8601String(),
    windowEndedAt: _buildAndroidFrameWindowEnd(
      deviceBootWallClockMs: deviceBootWallClockMs,
      measuredAtMs: measuredAtMs,
      summaryStartNs: summaryStartNs,
      lastFrameNs: bounds.lastFrameNs,
    ),
    timestampSource: 'estimated-from-device-uptime',
  );
}

({int? firstFrameNs, int? lastFrameNs}) _computeFrameBounds(
  List<AndroidFrameStatsRow> frames,
) {
  if (frames.isEmpty) return (firstFrameNs: null, lastFrameNs: null);
  return (
    firstFrameNs: frames.map((f) => f.intendedVsyncNs).reduce(
      (a, b) => a < b ? a : b,
    ),
    lastFrameNs: frames.map((f) => f.frameCompletedNs).reduce(
      (a, b) => a > b ? a : b,
    ),
  );
}

int? _computeWindowDurationMs(int? windowStartNs, int? windowEndNs) {
  if (windowStartNs == null || windowEndNs == null) return null;
  final ms = ((windowEndNs - windowStartNs) / 1000000).round();
  return ms < 0 ? 0 : ms;
}

String? _buildAndroidFrameWindowEnd({
  required int deviceBootWallClockMs,
  required int measuredAtMs,
  int? summaryStartNs,
  int? lastFrameNs,
}) {
  if (summaryStartNs != null) {
    return DateTime.fromMillisecondsSinceEpoch(measuredAtMs, isUtc: true)
        .toIso8601String();
  }
  if (lastFrameNs == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(
    deviceBootWallClockMs + (lastFrameNs / 1000000).round(),
    isUtc: true,
  ).toIso8601String();
}

int? _computeFrameWindowMs(List<AndroidFrameStatsRow> frames) {
  if (frames.isEmpty) return null;
  final bounds = _computeFrameBounds(frames);
  return _computeWindowDurationMs(bounds.firstFrameNs, bounds.lastFrameNs);
}

int? _matchSummaryInteger(String text, String label) {
  final escapedLabel = RegExp.escape(label);
  final match = RegExp(
    r'^\s*' + escapedLabel + r':\s*([0-9][0-9,]*)',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  return _parseNumericToken(match.group(1));
}

int? _parseNumericToken(String? token) {
  if (token == null) return null;
  final cleaned = token.replaceAll(',', '');
  final match = RegExp(r'^-?\d+(?:\.\d+)?').firstMatch(cleaned);
  if (match == null) return null;
  final value = double.tryParse(match.group(0) ?? '');
  if (value == null || !value.isFinite) return null;
  return value.toInt();
}
