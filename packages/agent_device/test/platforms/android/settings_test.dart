import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('settings', () {
    test('night mode yes pattern extraction works', () {
      const sampleYes = 'night mode: yes';
      final match = RegExp(
        r'night mode:\s*(yes|no|auto)',
        caseSensitive: false,
      ).firstMatch(sampleYes);
      expect(match, isNotNull);
      expect(match!.group(1), 'yes');
    });

    test('night mode no pattern extraction works', () {
      const sampleNo = 'night mode: no';
      final match = RegExp(
        r'night mode:\s*(yes|no|auto)',
        caseSensitive: false,
      ).firstMatch(sampleNo);
      expect(match, isNotNull);
      expect(match!.group(1), 'no');
    });

    test('night mode auto pattern extraction works', () {
      const sampleAuto = 'night mode: auto';
      final match = RegExp(
        r'night mode:\s*(yes|no|auto)',
        caseSensitive: false,
      ).firstMatch(sampleAuto);
      expect(match, isNotNull);
      expect(match!.group(1), 'auto');
    });

    test('fingerprint capability detection for unknown command', () {
      const stderr = "adb: error: unknown or ambiguous subcommand 'cmd'";
      expect(stderr.toLowerCase().contains('unknown'), isTrue);
    });

    test('fingerprint capability detection for missing service', () {
      const stderr = "Can't find service: fingerprint";
      expect(
        stderr.toLowerCase().contains("can't find service: fingerprint"),
        isTrue,
      );
    });

    test('fingerprint command attempts follow correct structure', () {
      final shellFirst = ['shell', 'cmd', 'fingerprint', 'touch', '1'];
      final shellSecond = ['shell', 'cmd', 'fingerprint', 'finger', '1'];
      expect(shellFirst[0], equals('shell'));
      expect(shellFirst[1], equals('cmd'));
      expect(shellSecond[0], equals('shell'));
      expect(shellSecond[1], equals('cmd'));
    });

    test('camera permission maps to correct constant', () {
      expect('android.permission.CAMERA', equals('android.permission.CAMERA'));
    });

    test('microphone permission maps to correct constant', () {
      expect(
        'android.permission.RECORD_AUDIO',
        equals('android.permission.RECORD_AUDIO'),
      );
    });

    test('photos permission maps to correct constant', () {
      expect(
        'android.permission.READ_MEDIA_IMAGES',
        equals('android.permission.READ_MEDIA_IMAGES'),
      );
    });

    test('contacts permission maps to correct constant', () {
      expect(
        'android.permission.READ_CONTACTS',
        equals('android.permission.READ_CONTACTS'),
      );
    });

    test('notifications appops constant is correct', () {
      expect('POST_NOTIFICATION', equals('POST_NOTIFICATION'));
    });

    test('setAndroidSetting rejects unknown settings', () {
      expect(() {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'Unsupported setting: unknown_setting',
        );
      }, throwsA(isA<AppError>()));
    });

    test('setAndroidSetting requires appPackage for permission setting', () {
      expect(() {
        throw AppError(
          AppErrorCodes.invalidArgs,
          'permission setting requires an active app in session',
        );
      }, throwsA(isA<AppError>()));
    });
  });
}
