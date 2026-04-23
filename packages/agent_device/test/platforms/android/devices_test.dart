/// Tests for devices.dart — Android device enumeration and emulator boot.
library;

import 'package:agent_device/src/platforms/android/devices.dart';
import 'package:test/test.dart';

void main() {
  group('parseAndroidEmulatorAvdNameOutput', () {
    test('parses single line AVD name', () {
      const output = 'Pixel_4_API_30';
      expect(
        parseAndroidEmulatorAvdNameOutput(output),
        equals('Pixel_4_API_30'),
      );
    });

    test('strips OK marker at end', () {
      const output = '''
Pixel_4_API_30
OK
''';
      expect(
        parseAndroidEmulatorAvdNameOutput(output),
        equals('Pixel_4_API_30'),
      );
    });

    test('returns null for empty output', () {
      expect(parseAndroidEmulatorAvdNameOutput(''), isNull);
    });

    test('handles output with extra lines before OK', () {
      const output = '''
Description: Pixel 4
Pixel_4_API_30
OK
''';
      final result = parseAndroidEmulatorAvdNameOutput(output);
      expect(result, isNotNull);
      expect(result, contains('Pixel_4_API_30'));
    });
  });

  group('parseAndroidTargetFromCharacteristics', () {
    test('detects TV from characteristics', () {
      const output = 'tv,nosdcard';
      expect(parseAndroidTargetFromCharacteristics(output), equals('tv'));
    });

    test('detects leanback feature as TV', () {
      const output = 'default,leanback';
      expect(parseAndroidTargetFromCharacteristics(output), equals('tv'));
    });

    test('case-insensitive detection', () {
      const output = 'TV,OTHER';
      expect(parseAndroidTargetFromCharacteristics(output), equals('tv'));
    });

    test('returns null for mobile device', () {
      const output = 'phone,nosdcard';
      expect(parseAndroidTargetFromCharacteristics(output), isNull);
    });
  });

  group('parseAndroidFeatureListForTv', () {
    test('detects leanback feature', () {
      const output =
          'feature:android.software.leanback\nfeature:android.hardware.bluetooth';
      expect(parseAndroidFeatureListForTv(output), isTrue);
    });

    test('detects leanback_only feature', () {
      const output = 'feature:android.software.leanback_only';
      expect(parseAndroidFeatureListForTv(output), isTrue);
    });

    test('detects television type feature', () {
      const output = 'feature:android.hardware.type.television';
      expect(parseAndroidFeatureListForTv(output), isTrue);
    });

    test('case-insensitive matching', () {
      const output = 'FEATURE:ANDROID.SOFTWARE.LEANBACK';
      expect(parseAndroidFeatureListForTv(output), isTrue);
    });

    test('returns false for mobile features', () {
      const output =
          'feature:android.hardware.touchscreen\nfeature:android.hardware.camera';
      expect(parseAndroidFeatureListForTv(output), isFalse);
    });

    test('returns false for empty output', () {
      expect(parseAndroidFeatureListForTv(''), isFalse);
    });
  });

  group('parseAndroidAvdList', () {
    test('parses single AVD name', () {
      const output = 'Pixel_4_API_30';
      final names = parseAndroidAvdList(output);
      expect(names, equals(['Pixel_4_API_30']));
    });

    test('parses multiple AVD names', () {
      const output = '''
Pixel_4_API_30
Pixel_3_API_29
Nexus_5X_API_28
''';
      final names = parseAndroidAvdList(output);
      expect(names, contains('Pixel_4_API_30'));
      expect(names, contains('Pixel_3_API_29'));
      expect(names, contains('Nexus_5X_API_28'));
    });

    test('filters out empty lines', () {
      const output = '''
Pixel_4_API_30


Pixel_3_API_29
''';
      final names = parseAndroidAvdList(output);
      expect(names.where((n) => n.isEmpty), isEmpty);
    });

    test('strips whitespace from names', () {
      const output = '''
  Pixel_4_API_30
  Pixel_3_API_29
''';
      final names = parseAndroidAvdList(output);
      expect(names, containsAll(['Pixel_4_API_30', 'Pixel_3_API_29']));
    });
  });

  group('resolveAndroidAvdName', () {
    test('returns exact match', () {
      final avdNames = ['Pixel_4_API_30', 'Pixel_3_API_29'];
      expect(
        resolveAndroidAvdName(avdNames, 'Pixel_4_API_30'),
        equals('Pixel_4_API_30'),
      );
    });

    test('returns normalized match', () {
      final avdNames = ['Pixel_4_API_30', 'Pixel_3_API_29'];
      expect(
        resolveAndroidAvdName(avdNames, 'Pixel 4 API 30'),
        equals('Pixel_4_API_30'),
      );
    });

    test('case-insensitive normalized matching', () {
      final avdNames = ['Pixel_4_API_30'];
      expect(
        resolveAndroidAvdName(avdNames, 'PIXEL 4 API 30'),
        equals('Pixel_4_API_30'),
      );
    });

    test('returns null for no match', () {
      final avdNames = ['Pixel_4_API_30'];
      expect(resolveAndroidAvdName(avdNames, 'Nexus_9_API_25'), isNull);
    });

    test('prefers exact match over normalized', () {
      final avdNames = ['Pixel_4_API_30', 'Pixel 4 API 30'];
      // Exact match should be returned first
      final result = resolveAndroidAvdName(avdNames, 'Pixel_4_API_30');
      expect(result, equals('Pixel_4_API_30'));
    });

    test('normalizes underscores to spaces', () {
      final avdNames = ['Pixel_4_API_30'];
      expect(
        resolveAndroidAvdName(avdNames, 'Pixel 4 API 30'),
        equals('Pixel_4_API_30'),
      );
    });

    test('normalizes multiple spaces to single space', () {
      final avdNames = ['Pixel_4_API_30'];
      expect(
        resolveAndroidAvdName(avdNames, 'Pixel    4    API    30'),
        equals('Pixel_4_API_30'),
      );
    });
  });
}
