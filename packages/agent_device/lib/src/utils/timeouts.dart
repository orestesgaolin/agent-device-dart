// Port of `agent-device/src/utils/timeouts.ts`.
//
// Timeout parsing and sleep utilities.
library;

/// Parses a timeout string (typically from environment variables or CLI args).
///
/// Returns [fallback] if [raw] is null, empty, or cannot be parsed as a number.
/// Ensures the result is at least [min] milliseconds.
int resolveTimeoutMs(String? raw, int fallback, int min) {
  if (raw == null || raw.isEmpty) return fallback;
  final parsed = int.tryParse(raw);
  if (parsed == null) return fallback;
  return (parsed / 1).floor() > min ? (parsed / 1).floor() : min;
}

/// Pauses execution for [ms] milliseconds.
Future<void> sleep(Duration duration) async {
  await Future<void>.delayed(duration);
}

/// Alias for [resolveTimeoutMs] — semantically marks the caller expects seconds.
/// Internally works with milliseconds like [resolveTimeoutMs].
int resolveTimeoutSeconds(String? raw, int fallback, int min) {
  return resolveTimeoutMs(raw, fallback, min);
}
