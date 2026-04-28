import 'package:agent_device/src/platforms/android/snapshot.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('isUiAutomationConflict', () {
    test('matches uiautomator_killed reason', () {
      final error = AppError(
        AppErrorCodes.commandFailed,
        'Android uiautomator dump failed: device killed the process.',
        details: {'reason': 'uiautomator_killed'},
      );
      expect(isUiAutomationConflict(error), isTrue);
    });

    test('matches "Killed" + "uiautomator" in message', () {
      final error = AppError(
        AppErrorCodes.commandFailed,
        'Android uiautomator dump was Killed before producing output.',
      );
      expect(isUiAutomationConflict(error), isTrue);
    });

    test('matches "already registered" message', () {
      final error = AppError(
        AppErrorCodes.commandFailed,
        'UiAutomationService already registered!',
      );
      expect(isUiAutomationConflict(error), isTrue);
    });

    test('matches helper parse failure (concurrent access)', () {
      final error = AppError(
        AppErrorCodes.commandFailed,
        'Android snapshot helper output could not be parsed',
      );
      expect(isUiAutomationConflict(error), isTrue);
    });

    test('does not match unrelated command failures', () {
      final error = AppError(
        AppErrorCodes.commandFailed,
        'adb: device not found',
      );
      expect(isUiAutomationConflict(error), isFalse);
    });

    test('does not match non-AppError exceptions', () {
      expect(isUiAutomationConflict(Exception('random')), isFalse);
      expect(isUiAutomationConflict('a string'), isFalse);
    });

    test('does not match invalid args errors', () {
      final error = AppError(
        AppErrorCodes.invalidArgs,
        'snapshot requires something',
      );
      expect(isUiAutomationConflict(error), isFalse);
    });

    test('does not match timeout errors', () {
      final error = AppError(
        AppErrorCodes.commandFailed,
        'Android UI hierarchy dump timed out',
        details: {'timeoutMs': 8000},
      );
      expect(isUiAutomationConflict(error), isFalse);
    });
  });
}
