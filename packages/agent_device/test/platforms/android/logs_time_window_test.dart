// Unit coverage for the `adb logcat -T` time-window resolver.

import 'package:agent_device/src/platforms/android/android_backend.dart';
import 'package:test/test.dart';

void main() {
  group('resolveAdbLogcatTimeWindow', () {
    final anchor = DateTime(2026, 4, 24, 13, 0, 0, 0);

    test('null input defaults to 5 minutes back', () {
      expect(
        resolveAdbLogcatTimeWindow(null, now: anchor),
        '04-24 12:55:00.000',
      );
    });

    test('empty input defaults to 5 minutes back', () {
      expect(resolveAdbLogcatTimeWindow('', now: anchor), '04-24 12:55:00.000');
    });

    test('parses 30s as 30 seconds back', () {
      expect(
        resolveAdbLogcatTimeWindow('30s', now: anchor),
        '04-24 12:59:30.000',
      );
    });

    test('parses 1h as 1 hour back', () {
      expect(
        resolveAdbLogcatTimeWindow('1h', now: anchor),
        '04-24 12:00:00.000',
      );
    });

    test('parses 2d as 2 days back', () {
      expect(
        resolveAdbLogcatTimeWindow('2d', now: anchor),
        '04-22 13:00:00.000',
      );
    });

    test('pads single-digit fields', () {
      final earlyMorning = DateTime(2026, 1, 5, 3, 4, 5, 6);
      expect(
        resolveAdbLogcatTimeWindow('1s', now: earlyMorning),
        '01-05 03:04:04.006',
      );
    });

    test('passes absolute-looking input through unchanged', () {
      expect(
        resolveAdbLogcatTimeWindow('04-24 12:00:00.000', now: anchor),
        '04-24 12:00:00.000',
      );
    });
  });
}
