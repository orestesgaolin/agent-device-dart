// Port of agent-device/src/platforms/android/perf-frame-analysis.ts

import '../perf_utils.dart' show roundOneDecimal;

export '../perf_utils.dart' show roundOneDecimal;

const int _maxWorstWindows = 3;
// Dropped frames separated by more than 500ms are reported as separate jank clusters.
const int _jankWindowGapNs = 500000000;
const int _minDisplayFrameIntervalNs = 4000000;
const int _maxDisplayFrameIntervalNs = 50000000;

/// A single rendered frame record from framestats output.
class AndroidFrameStatsRow {
  final int intendedVsyncNs;
  final int frameCompletedNs;
  final int durationNs;

  const AndroidFrameStatsRow({
    required this.intendedVsyncNs,
    required this.frameCompletedNs,
    required this.durationNs,
  });
}

/// A window of consecutive dropped frames.
class AndroidFrameDropWindow {
  final int startOffsetMs;
  final int endOffsetMs;
  final String? startAt;
  final String? endAt;
  final int missedDeadlineFrameCount;
  final double worstFrameMs;

  const AndroidFrameDropWindow({
    required this.startOffsetMs,
    required this.endOffsetMs,
    this.startAt,
    this.endAt,
    required this.missedDeadlineFrameCount,
    required this.worstFrameMs,
  });
}

/// Derives the frame deadline (display interval) in nanoseconds from the
/// median inter-vsync delta of consecutive valid frames.
int? deriveFrameDeadlineNs(List<AndroidFrameStatsRow> frames) {
  final intendedVsyncs = _uniqueSortedInts(
    frames.map((f) => f.intendedVsyncNs).toList(),
  );
  final deltas = <int>[];
  for (int i = 1; i < intendedVsyncs.length; i++) {
    final delta = intendedVsyncs[i] - intendedVsyncs[i - 1];
    if (delta >= _minDisplayFrameIntervalNs &&
        delta <= _maxDisplayFrameIntervalNs) {
      deltas.add(delta);
    }
  }
  if (deltas.isEmpty) return null;
  return _median(deltas);
}

/// Returns the subset of [frames] that are considered dropped.
///
/// If [summaryDroppedFrameCount] is provided it is authoritative: the slowest
/// N rows are selected to approximate jank attribution. Otherwise all rows
/// whose duration exceeds [frameDeadlineNs] are returned.
List<AndroidFrameStatsRow> selectDroppedFrameRows({
  required List<AndroidFrameStatsRow> frames,
  int? frameDeadlineNs,
  int? summaryDroppedFrameCount,
}) {
  if (summaryDroppedFrameCount != null) {
    if (summaryDroppedFrameCount <= 0) return [];
    // Android's janky-frame summary is authoritative, but framestats rows do
    // not expose the exact summary classification. Use the slowest rows only
    // for approximate attribution.
    final sorted = [...frames]
      ..sort((a, b) => b.durationNs.compareTo(a.durationNs));
    return (sorted.take(summaryDroppedFrameCount).toList()
          ..sort((a, b) => a.intendedVsyncNs.compareTo(b.intendedVsyncNs)));
  }
  if (frameDeadlineNs == null) return [];
  return frames.where((f) => f.durationNs > frameDeadlineNs).toList();
}

/// Groups dropped frames into time clusters and returns the worst ones
/// (up to [_maxWorstWindows]), sorted by start offset.
List<AndroidFrameDropWindow> buildWorstFrameDropWindows({
  required List<AndroidFrameStatsRow> frames,
  int? windowStartNs,
  required int measuredAtMs,
  int? uptimeMs,
}) {
  if (frames.isEmpty || windowStartNs == null) return [];

  final windows = <List<AndroidFrameStatsRow>>[];
  var current = <AndroidFrameStatsRow>[];
  for (final frame in frames) {
    final previous = current.isEmpty ? null : current.last;
    if (previous == null ||
        frame.intendedVsyncNs - previous.frameCompletedNs <=
            _jankWindowGapNs) {
      current.add(frame);
      continue;
    }
    windows.add(current);
    current = [frame];
  }
  if (current.isNotEmpty) windows.add(current);

  final built =
      windows
          .map(
            (windowFrames) => _buildFrameDropWindow(
              frames: windowFrames,
              windowStartNs: windowStartNs,
              measuredAtMs: measuredAtMs,
              uptimeMs: uptimeMs,
            ),
          )
          .toList()
        ..sort(
          (a, b) =>
              a.missedDeadlineFrameCount != b.missedDeadlineFrameCount
                  ? b.missedDeadlineFrameCount - a.missedDeadlineFrameCount
                  : b.worstFrameMs.compareTo(a.worstFrameMs),
        );

  return (built.take(_maxWorstWindows).toList()
    ..sort((a, b) => a.startOffsetMs.compareTo(b.startOffsetMs)));
}

AndroidFrameDropWindow _buildFrameDropWindow({
  required List<AndroidFrameStatsRow> frames,
  required int windowStartNs,
  required int measuredAtMs,
  int? uptimeMs,
}) {
  final startNs = frames.map((f) => f.intendedVsyncNs).reduce(
    (a, b) => a < b ? a : b,
  );
  final endNs = frames.map((f) => f.frameCompletedNs).reduce(
    (a, b) => a > b ? a : b,
  );
  final startOffsetRaw = ((startNs - windowStartNs) / 1000000).round();
  final startOffsetMs = startOffsetRaw < 0 ? 0 : startOffsetRaw;
  final endOffsetMsRaw = ((endNs - windowStartNs) / 1000000).round();
  final endOffsetMs =
      endOffsetMsRaw < startOffsetMs ? startOffsetMs : endOffsetMsRaw;
  final int? base = uptimeMs != null ? measuredAtMs - uptimeMs : null;
  return AndroidFrameDropWindow(
    startOffsetMs: startOffsetMs,
    endOffsetMs: endOffsetMs,
    startAt:
        base == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
              base + (startNs / 1000000).round(),
              isUtc: true,
            ).toIso8601String(),
    endAt:
        base == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
              base + (endNs / 1000000).round(),
              isUtc: true,
            ).toIso8601String(),
    missedDeadlineFrameCount: frames.length,
    worstFrameMs: roundOneDecimal(
      frames.map((f) => f.durationNs).reduce((a, b) => a > b ? a : b) /
          1000000,
    ),
  );
}

List<int> _uniqueSortedInts(List<int> values) {
  return values.toSet().toList()..sort();
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}
