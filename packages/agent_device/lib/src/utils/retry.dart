// Port of `agent-device/src/utils/retry.ts`.
//
// Generic retry logic with exponential backoff, jitter, and deadline support.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, stderr;
import 'dart:math' show Random, max, min;
import 'diagnostics.dart';
import 'errors.dart';

/// Context information about a retry attempt.
class RetryAttemptContext {
  final int attempt;
  final int maxAttempts;
  final Deadline? deadline;

  RetryAttemptContext({
    required this.attempt,
    required this.maxAttempts,
    this.deadline,
  });
}

/// Retry policy configuration.
class RetryPolicy {
  final int maxAttempts;
  final int baseDelayMs;
  final int maxDelayMs;
  final double jitter;
  final bool Function(Object error, int attempt)? shouldRetry;

  RetryPolicy({
    required this.maxAttempts,
    required this.baseDelayMs,
    required this.maxDelayMs,
    required this.jitter,
    this.shouldRetry,
  });
}

/// Options for retry behavior.
class RetryOptions {
  final int? attempts;
  final int? baseDelayMs;
  final int? maxDelayMs;
  final double? jitter;
  final bool Function(Object error, int attempt)? shouldRetry;

  RetryOptions({
    this.attempts,
    this.baseDelayMs,
    this.maxDelayMs,
    this.jitter,
    this.shouldRetry,
  });
}

/// Telemetry event from a retry operation.
class RetryTelemetryEvent {
  final String? phase;
  final String
  event; // 'attempt_failed' | 'retry_scheduled' | 'succeeded' | 'exhausted'
  final int attempt;
  final int maxAttempts;
  final int? delayMs;
  final int? elapsedMs;
  final int? remainingMs;
  final String? reason;

  RetryTelemetryEvent({
    this.phase,
    required this.event,
    required this.attempt,
    required this.maxAttempts,
    this.delayMs,
    this.elapsedMs,
    this.remainingMs,
    this.reason,
  });

  Map<String, Object?> toJson() => {
    if (phase != null) 'phase': phase,
    'event': event,
    'attempt': attempt,
    'maxAttempts': maxAttempts,
    if (delayMs != null) 'delayMs': delayMs,
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
    if (remainingMs != null) 'remainingMs': remainingMs,
    if (reason != null) 'reason': reason,
  };
}

/// Deadline for timeout-bounded retry.
class Deadline {
  final int _startedAtMs;
  final int _expiresAtMs;

  Deadline._(int startedAtMs, int timeoutMs)
    : _startedAtMs = startedAtMs,
      _expiresAtMs = startedAtMs + max(0, timeoutMs);

  /// Creates a deadline from a timeout duration.
  factory Deadline.fromTimeoutMs(int timeoutMs, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return Deadline._(now, timeoutMs);
  }

  /// Returns remaining milliseconds until expiration.
  int remainingMs({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return max(0, _expiresAtMs - now);
  }

  /// Returns elapsed milliseconds since creation.
  int elapsedMs({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return max(0, now - _startedAtMs);
  }

  /// Returns true if the deadline has passed.
  bool isExpired({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return remainingMs(nowMs: now) <= 0;
  }
}

/// Profile for timeout bounds (startup + operation phases).
class TimeoutProfile {
  final int startupMs;
  final int operationMs;
  final int totalMs;

  TimeoutProfile({
    required this.startupMs,
    required this.operationMs,
    required this.totalMs,
  });
}

/// Built-in timeout profiles for common operations.
final Map<String, TimeoutProfile> timeoutProfiles = {
  'ios_boot': TimeoutProfile(
    startupMs: 120000,
    operationMs: 20000,
    totalMs: 120000,
  ),
  'ios_runner_connect': TimeoutProfile(
    startupMs: 120000,
    operationMs: 15000,
    totalMs: 120000,
  ),
  'android_boot': TimeoutProfile(
    startupMs: 60000,
    operationMs: 10000,
    totalMs: 60000,
  ),
};

/// Returns true if an environment variable is truthy.
bool isEnvTruthy(String? value) {
  return [
    '1',
    'true',
    'yes',
    'on',
  ].contains((value ?? '').trim().toLowerCase());
}

final bool _retryLogsEnabled = isEnvTruthy(
  Platform.environment['AGENT_DEVICE_RETRY_LOGS'],
);

const int _defaultAttempts = 3;
const int _defaultBaseDelayMs = 200;
const int _defaultMaxDelayMs = 2000;
const double _defaultJitter = 0.2;

/// Retries an async operation with exponential backoff.
///
/// Calls [fn] repeatedly until it succeeds or max attempts is reached.
/// Between attempts, waits with exponential backoff + jitter.
/// If [deadline] is set, stops retrying when time expires (but always tries at least once).
Future<T> retryWithPolicy<T>(
  Future<T> Function(RetryAttemptContext context) fn,
  RetryPolicy? policy, {
  Deadline? deadline,
  String? phase,
  CancelToken? signal,
  String Function(Object error)? classifyReason,
  void Function(RetryTelemetryEvent event)? onEvent,
}) async {
  final merged = RetryPolicy(
    maxAttempts: policy?.maxAttempts ?? _defaultAttempts,
    baseDelayMs: policy?.baseDelayMs ?? _defaultBaseDelayMs,
    maxDelayMs: policy?.maxDelayMs ?? _defaultMaxDelayMs,
    jitter: policy?.jitter ?? _defaultJitter,
    shouldRetry: policy?.shouldRetry,
  );

  Object? lastError;
  for (int attempt = 1; attempt <= merged.maxAttempts; attempt++) {
    if ((signal?.isAborted) == true) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'request canceled',
        details: {'reason': 'request_canceled'},
      );
    }
    if ((deadline?.isExpired()) == true && attempt > 1) break;

    try {
      final result = await fn(
        RetryAttemptContext(
          attempt: attempt,
          maxAttempts: merged.maxAttempts,
          deadline: deadline,
        ),
      );
      onEvent?.call(
        RetryTelemetryEvent(
          phase: phase,
          event: 'succeeded',
          attempt: attempt,
          maxAttempts: merged.maxAttempts,
          elapsedMs: deadline?.elapsedMs(),
          remainingMs: deadline?.remainingMs(),
        ),
      );
      _publishRetryEvent(
        RetryTelemetryEvent(
          phase: phase,
          event: 'succeeded',
          attempt: attempt,
          maxAttempts: merged.maxAttempts,
          elapsedMs: deadline?.elapsedMs(),
          remainingMs: deadline?.remainingMs(),
        ),
      );
      return result;
    } catch (err) {
      lastError = err;
      final reason = classifyReason?.call(err);
      final failedEvent = RetryTelemetryEvent(
        phase: phase,
        event: 'attempt_failed',
        attempt: attempt,
        maxAttempts: merged.maxAttempts,
        elapsedMs: deadline?.elapsedMs(),
        remainingMs: deadline?.remainingMs(),
        reason: reason,
      );
      onEvent?.call(failedEvent);
      _publishRetryEvent(failedEvent);

      if (attempt >= merged.maxAttempts) break;
      if (merged.shouldRetry != null && !merged.shouldRetry!(err, attempt)) {
        break;
      }

      final delay = _computeDelay(
        merged.baseDelayMs,
        merged.maxDelayMs,
        merged.jitter,
        attempt,
      );
      final boundedDelay = deadline != null
          ? min(delay, deadline.remainingMs())
          : delay;

      if (boundedDelay <= 0) break;

      final retryEvent = RetryTelemetryEvent(
        phase: phase,
        event: 'retry_scheduled',
        attempt: attempt,
        maxAttempts: merged.maxAttempts,
        delayMs: boundedDelay,
        elapsedMs: deadline?.elapsedMs(),
        remainingMs: deadline?.remainingMs(),
        reason: reason,
      );
      onEvent?.call(retryEvent);
      _publishRetryEvent(retryEvent);

      await _sleep(boundedDelay, signal);
    }
  }

  final exhaustedEvent = RetryTelemetryEvent(
    phase: phase,
    event: 'exhausted',
    attempt: merged.maxAttempts,
    maxAttempts: merged.maxAttempts,
    elapsedMs: deadline?.elapsedMs(),
    remainingMs: deadline?.remainingMs(),
    reason: lastError != null ? classifyReason?.call(lastError) : null,
  );
  onEvent?.call(exhaustedEvent);
  _publishRetryEvent(exhaustedEvent);

  if (lastError != null) throw lastError;
  throw AppError(AppErrorCodes.commandFailed, 'retry failed');
}

/// Retries an async operation with default backoff strategy.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int? attempts,
  int? baseDelayMs,
  int? maxDelayMs,
  double? jitter,
  bool Function(Object error, int attempt)? shouldRetry,
}) {
  return retryWithPolicy(
    (_) => fn(),
    RetryPolicy(
      maxAttempts: attempts ?? _defaultAttempts,
      baseDelayMs: baseDelayMs ?? _defaultBaseDelayMs,
      maxDelayMs: maxDelayMs ?? _defaultMaxDelayMs,
      jitter: jitter ?? _defaultJitter,
      shouldRetry: shouldRetry,
    ),
  );
}

/// Computes exponential backoff delay with jitter.
int _computeDelay(int base, int maxDelay, double jitterFactor, int attempt) {
  final exp = min(maxDelay, (base * (1 << (attempt - 1))).toInt());
  final jitterAmount = (exp * jitterFactor).toInt();
  final jitterVal = (Random().nextDouble() * 2 - 1) * jitterAmount;
  return max(0, (exp + jitterVal).toInt());
}

/// Sleeps for [ms] milliseconds, can be canceled via [signal].
Future<void> _sleep(int ms, CancelToken? signal) async {
  if ((signal?.isAborted) == true) return;

  if (signal == null) {
    await Future<void>.delayed(Duration(milliseconds: ms));
    return;
  }

  final completer = Completer<void>();
  final timer = Timer(Duration(milliseconds: ms), () {
    if (!completer.isCompleted) completer.complete();
  });

  void onAbort() {
    timer.cancel();
    if (!completer.isCompleted) completer.complete();
  }

  signal._addAbortListener(onAbort);
  await completer.future;
  signal._removeAbortListener(onAbort);
}

/// Publishes a retry event to diagnostics and stderr (if enabled).
void _publishRetryEvent(RetryTelemetryEvent event) {
  final level = event.event == 'attempt_failed' || event.event == 'exhausted'
      ? DiagnosticLevel.warn
      : DiagnosticLevel.debug;
  emitDiagnostic(
    EmitDiagnosticOptions(level: level, phase: 'retry', data: event.toJson()),
  );
  if (!_retryLogsEnabled) return;
  stderr.writeln('[agent-device][retry] ${jsonEncode(event.toJson())}');
}

/// Token for canceling operations.
class CancelToken {
  bool _cancelled = false;

  final List<void Function()> _listeners = [];

  /// Marks this token as aborted.
  void abort() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners) {
      listener();
    }
    _listeners.clear();
  }

  /// Returns true if this token has been aborted.
  bool get isAborted => _cancelled;

  void _addAbortListener(void Function() callback) {
    if (_cancelled) {
      callback();
    } else {
      _listeners.add(callback);
    }
  }

  void _removeAbortListener(void Function() callback) {
    _listeners.remove(callback);
  }
}
