import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('asAppError', () {
    test('passes through AppError', () {
      final err = AppError(AppErrorCodes.invalidArgs, 'bad');
      expect(identical(asAppError(err), err), isTrue);
    });

    test('wraps plain Exception as UNKNOWN', () {
      final err = asAppError(const FormatException('boom'));
      expect(err.code, AppErrorCodes.unknown);
      expect(err.message, contains('boom'));
    });

    test('wraps non-Error values in details', () {
      final err = asAppError(42);
      expect(err.code, AppErrorCodes.unknown);
      expect(err.details?['err'], 42);
    });
  });

  group('normalizeError', () {
    test('attaches default hint for known code', () {
      final norm = normalizeError(AppError(AppErrorCodes.invalidArgs, 'bad'));
      expect(norm.code, AppErrorCodes.invalidArgs);
      expect(norm.hint, contains('--help'));
      expect(norm.details, isNull);
    });

    test('prefers detail hint over code default', () {
      final err = AppError(
        AppErrorCodes.invalidArgs,
        'bad',
        details: {'hint': 'custom hint'},
      );
      expect(normalizeError(err).hint, 'custom hint');
    });

    test('redacts sensitive keys in details', () {
      final err = AppError(
        AppErrorCodes.commandFailed,
        'boom',
        details: {'token': 'abc123', 'other': 'value'},
      );
      final norm = normalizeError(err);
      expect(norm.details?['token'], '[REDACTED]');
      expect(norm.details?['other'], 'value');
    });

    test('propagates context diagnosticId/logPath', () {
      final err = AppError(AppErrorCodes.commandFailed, 'boom');
      final norm = normalizeError(
        err,
        diagnosticId: 'diag-1',
        logPath: '/tmp/x',
      );
      expect(norm.diagnosticId, 'diag-1');
      expect(norm.logPath, '/tmp/x');
    });

    test('details-provided diagnostic meta wins over context', () {
      final err = AppError(
        AppErrorCodes.commandFailed,
        'boom',
        details: {'diagnosticId': 'from-details'},
      );
      final norm = normalizeError(err, diagnosticId: 'from-ctx');
      expect(norm.diagnosticId, 'from-details');
    });

    test('strips diagnostic meta from surfaced details', () {
      final err = AppError(
        AppErrorCodes.commandFailed,
        'boom',
        details: {'hint': 'h', 'diagnosticId': 'd', 'logPath': 'p', 'kept': 1},
      );
      final norm = normalizeError(err);
      expect(norm.details, {'kept': 1});
    });

    test('enriches COMMAND_FAILED message with first stderr line', () {
      final err = AppError(
        AppErrorCodes.commandFailed,
        'Command failed',
        details: {
          'processExitError': true,
          'stderr':
              'An error was encountered processing the command\nreal reason here\ntail',
        },
      );
      final norm = normalizeError(err);
      expect(norm.message, 'real reason here');
    });

    test('does not enrich when processExitError absent', () {
      final err = AppError(
        AppErrorCodes.commandFailed,
        'original',
        details: {'stderr': 'some noise'},
      );
      expect(normalizeError(err).message, 'original');
    });
  });

  test('toAppErrorCode falls back when empty', () {
    expect(toAppErrorCode(null), AppErrorCodes.commandFailed);
    expect(toAppErrorCode(''), AppErrorCodes.commandFailed);
    expect(toAppErrorCode('CUSTOM'), 'CUSTOM');
  });
}
