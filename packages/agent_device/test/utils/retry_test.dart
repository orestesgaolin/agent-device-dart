import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/retry.dart';
import 'package:test/test.dart';

void main() {
  group('retry', () {
    group('Deadline', () {
      test('isExpired returns false when not expired', () {
        final deadline = Deadline.fromTimeoutMs(5000);
        expect(deadline.isExpired(), false);
      });

      test('isExpired returns true when expired', () {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final deadline = Deadline.fromTimeoutMs(100, nowMs: nowMs);
        expect(deadline.isExpired(nowMs: nowMs + 200), true);
      });

      test('remainingMs decreases over time', () {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final deadline = Deadline.fromTimeoutMs(1000, nowMs: nowMs);
        expect(deadline.remainingMs(nowMs: nowMs), 1000);
        expect(deadline.remainingMs(nowMs: nowMs + 500), 500);
      });

      test('elapsedMs increases over time', () {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final deadline = Deadline.fromTimeoutMs(5000, nowMs: nowMs);
        expect(deadline.elapsedMs(nowMs: nowMs), 0);
        expect(deadline.elapsedMs(nowMs: nowMs + 300), 300);
      });
    });

    group('isEnvTruthy', () {
      test('recognizes truthy values', () {
        expect(isEnvTruthy('1'), true);
        expect(isEnvTruthy('true'), true);
        expect(isEnvTruthy('yes'), true);
        expect(isEnvTruthy('on'), true);
      });

      test('recognizes falsy values', () {
        expect(isEnvTruthy('0'), false);
        expect(isEnvTruthy('false'), false);
        expect(isEnvTruthy('no'), false);
        expect(isEnvTruthy('off'), false);
      });

      test('is case-insensitive', () {
        expect(isEnvTruthy('TRUE'), true);
        expect(isEnvTruthy('Yes'), true);
        expect(isEnvTruthy('ON'), true);
      });

      test('handles null', () {
        expect(isEnvTruthy(null), false);
      });

      test('trims whitespace', () {
        expect(isEnvTruthy('  true  '), true);
        expect(isEnvTruthy(' 1 '), true);
      });
    });

    group('withRetry', () {
      test('returns immediately on success', () async {
        var attempts = 0;
        final result = await withRetry(() async {
          attempts++;
          return 'success';
        });
        expect(result, 'success');
        expect(attempts, 1);
      });

      test('retries on failure then succeeds', () async {
        var attempts = 0;
        final result = await withRetry(
          () async {
            attempts++;
            if (attempts < 3) {
              throw Exception('attempt $attempts failed');
            }
            return 'success';
          },
          attempts: 5,
          baseDelayMs: 1, // Minimal delay for tests
        );
        expect(result, 'success');
        expect(attempts, 3);
      });

      test('exhausts retries and throws', () async {
        var attempts = 0;
        var caught = false;
        try {
          await withRetry(
            () async {
              attempts++;
              throw AppError(AppErrorCodes.commandFailed, 'always fails');
            },
            attempts: 3,
            baseDelayMs: 1,
          );
        } on AppError {
          caught = true;
        }
        expect(caught, true);
        expect(attempts, 3);
      });

      test('respects shouldRetry predicate', () async {
        var attempts = 0;
        expect(
          () => withRetry(
            () async {
              attempts++;
              throw Exception('error');
            },
            attempts: 5,
            baseDelayMs: 1,
            shouldRetry: (error, attempt) => false, // Don't retry
          ),
          throwsException,
        );
        expect(attempts, 1); // Only one attempt
      });
    });

    group('retryWithPolicy', () {
      test('respects maxAttempts from policy', () async {
        var attempts = 0;
        final policy = RetryPolicy(
          maxAttempts: 2,
          baseDelayMs: 1,
          maxDelayMs: 100,
          jitter: 0.1,
        );
        var caught = false;
        try {
          await retryWithPolicy((_) async {
            attempts++;
            throw AppError(AppErrorCodes.commandFailed, 'fail');
          }, policy);
        } on AppError {
          caught = true;
        }
        expect(caught, true);
        expect(attempts, 2);
      });

      test('reports telemetry events', () async {
        final events = <RetryTelemetryEvent>[];
        final policy = RetryPolicy(
          maxAttempts: 2,
          baseDelayMs: 1,
          maxDelayMs: 100,
          jitter: 0.1,
        );
        try {
          await retryWithPolicy(
            (_) async {
              throw AppError(AppErrorCodes.commandFailed, 'fail');
            },
            policy,
            onEvent: (event) => events.add(event),
            phase: 'test_phase',
          );
        } catch (_) {
          // Expected to fail
        }
        expect(events.isNotEmpty, true);
        expect(events.where((e) => e.event == 'attempt_failed'), isNotEmpty);
        expect(events.where((e) => e.event == 'exhausted'), isNotEmpty);
      });

      test('respects deadline', () async {
        var attempts = 0;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final deadline = Deadline.fromTimeoutMs(50, nowMs: nowMs);
        final policy = RetryPolicy(
          maxAttempts: 10,
          baseDelayMs: 20,
          maxDelayMs: 100,
          jitter: 0.0,
        );
        try {
          await retryWithPolicy(
            (context) async {
              attempts++;
              throw AppError(AppErrorCodes.commandFailed, 'fail');
            },
            policy,
            deadline: deadline,
          );
        } catch (_) {
          // Expected to fail
        }
        // Should stop retrying after deadline expires
        expect(attempts, lessThan(10));
      });
    });

    group('CancelToken', () {
      test('starts not aborted', () {
        final token = CancelToken();
        expect(token.isAborted, false);
      });

      test('can be aborted', () {
        final token = CancelToken();
        token.abort();
        expect(token.isAborted, true);
      });

      test('abort is idempotent', () {
        final token = CancelToken();
        token.abort();
        token.abort();
        expect(token.isAborted, true);
      });
    });

    group('TimeoutProfile', () {
      test('predefined profiles exist', () {
        expect(timeoutProfiles.containsKey('ios_boot'), true);
        expect(timeoutProfiles.containsKey('android_boot'), true);
        expect(timeoutProfiles['ios_boot']!.totalMs, 120000);
      });
    });
  });
}
