import 'package:agent_device/src/utils/timeouts.dart';
import 'package:test/test.dart';

void main() {
  group('timeouts', () {
    group('resolveTimeoutMs', () {
      test('returns fallback when raw is null', () {
        const fallback = 5000;
        final result = resolveTimeoutMs(null, fallback, 0);
        expect(result, fallback);
      });

      test('returns fallback when raw is empty string', () {
        const fallback = 5000;
        final result = resolveTimeoutMs('', fallback, 0);
        expect(result, fallback);
      });

      test('returns fallback when raw is not a number', () {
        const fallback = 5000;
        final result = resolveTimeoutMs('invalid', fallback, 0);
        expect(result, fallback);
      });

      test('parses valid integer', () {
        final result = resolveTimeoutMs('3000', 0, 0);
        expect(result, 3000);
      });

      test('enforces minimum timeout', () {
        final result = resolveTimeoutMs('100', 5000, 1000);
        expect(result, 1000); // min is enforced
      });

      test('returns parsed value when above minimum', () {
        final result = resolveTimeoutMs('5000', 1000, 1000);
        expect(result, 5000);
      });
    });

    group('resolveTimeoutSeconds', () {
      test('behaves identically to resolveTimeoutMs', () {
        final ms = resolveTimeoutMs('2000', 5000, 100);
        final sec = resolveTimeoutSeconds('2000', 5000, 100);
        expect(sec, ms);
      });
    });

    group('sleep', () {
      test('completes after specified duration', () async {
        final stopwatch = Stopwatch()..start();
        await sleep(const Duration(milliseconds: 10));
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(10));
      });
    });
  });
}
