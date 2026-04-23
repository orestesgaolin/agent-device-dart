@TestOn('mac-os || linux')
library;

import 'dart:io';
import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';
import 'package:test/test.dart';

void main() {
  group('exec', () {
    group('runCmd', () {
      test('runs a simple command and captures stdout', () async {
        final result = await runCmd('echo', ['hello']);
        expect(result.stdout.trim(), equals('hello'));
        expect(result.stderr, isEmpty);
        expect(result.exitCode, equals(0));
      });

      test('captures stderr', () async {
        final result = await runCmd('sh', [
          '-c',
          'echo error >&2',
        ], const ExecOptions(allowFailure: true));
        expect(result.stderr.trim(), equals('error'));
        expect(result.exitCode, equals(0));
      });

      test('throws on missing binary', () async {
        expect(
          () => runCmd('nonexistent-command-xyz-123', []),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.toolMissing),
            ),
          ),
        );
      });

      test('throws on non-zero exit with allowFailure=false', () async {
        expect(
          () => runCmd('sh', ['-c', 'exit 42']),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.commandFailed),
            ),
          ),
        );
      });

      test('allows failure with allowFailure=true', () async {
        final result = await runCmd('sh', [
          '-c',
          'exit 7',
        ], const ExecOptions(allowFailure: true));
        expect(result.exitCode, equals(7));
      });

      test('handles stdin', () async {
        final result = await runCmd(
          'cat',
          [],
          const ExecOptions(stdin: 'test input'),
        );
        expect(result.stdout, equals('test input'));
      });

      test('times out after timeoutMs', () async {
        expect(
          () => runCmd('sleep', ['10'], const ExecOptions(timeoutMs: 200)),
          throwsA(
            isA<AppError>()
                .having(
                  (e) => e.code,
                  'code',
                  equals(AppErrorCodes.commandFailed),
                )
                .having((e) => e.message, 'message', contains('timed out')),
          ),
        );
      });

      test('preserves exit code in error details', () async {
        try {
          await runCmd('sh', ['-c', 'exit 99']);
          fail('should throw');
        } on AppError catch (e) {
          expect(e.details?['exitCode'], equals(99));
        }
      });
    });

    group('runCmdSync', () {
      test('runs a simple command synchronously', () {
        final result = runCmdSync('echo', ['hello']);
        expect(result.stdout.trim(), equals('hello'));
        expect(result.exitCode, equals(0));
      });

      test('throws on missing binary', () {
        expect(
          () => runCmdSync('nonexistent-command-xyz-123', []),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.toolMissing),
            ),
          ),
        );
      });

      test('throws on non-zero exit with allowFailure=false', () {
        expect(
          () => runCmdSync('sh', ['-c', 'exit 42']),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.commandFailed),
            ),
          ),
        );
      });

      test('allows failure with allowFailure=true', () {
        final result = runCmdSync('sh', [
          '-c',
          'exit 7',
        ], const ExecOptions(allowFailure: true));
        expect(result.exitCode, equals(7));
      });

      test('timeoutMs is silently ignored for sync (Dart limitation)', () {
        // Note: Dart's Process.runSync does not support timeouts.
        // This is a fundamental API difference from Node.
        // The timeoutMs parameter exists for API parity but has no effect.
        final result = runCmdSync('echo', [
          'test',
        ], const ExecOptions(timeoutMs: 200));
        expect(result.exitCode, equals(0));
      });
    });

    group('whichCmd', () {
      test('returns true for a command in PATH', () async {
        final exists = await whichCmd('echo');
        expect(exists, isTrue);
      });

      test('returns false for a command not in PATH', () async {
        final exists = await whichCmd('nonexistent-command-xyz-123');
        expect(exists, isFalse);
      });

      test('returns false for invalid command syntax', () async {
        final exists = await whichCmd('../relative/path/cmd');
        expect(exists, isFalse);
      });
    });

    group('runCmdStreaming', () {
      test('invokes onStdoutChunk callback', () async {
        final chunks = <String>[];
        await runCmdStreaming('echo', [
          'hello',
        ], ExecStreamOptions(onStdoutChunk: (chunk) => chunks.add(chunk)));
        expect(chunks, isNotEmpty);
        expect(chunks.join('').trim(), equals('hello'));
      });

      test('invokes onStderrChunk callback', () async {
        final chunks = <String>[];
        await runCmdStreaming(
          'sh',
          ['-c', 'echo error >&2'],
          ExecStreamOptions(
            allowFailure: true,
            onStderrChunk: (chunk) => chunks.add(chunk),
          ),
        );
        expect(chunks, isNotEmpty);
        expect(chunks.join('').trim(), equals('error'));
      });

      test('invokes onSpawn callback', () async {
        Process? capturedProcess;
        await runCmdStreaming('echo', [
          'test',
        ], ExecStreamOptions(onSpawn: (p) => capturedProcess = p));
        expect(capturedProcess, isNotNull);
        expect(capturedProcess!.pid, greaterThan(0));
      });
    });

    group('resolveExecutableOverridePath', () {
      test('returns path if valid executable exists', () async {
        final result = await resolveExecutableOverridePath(
          '/bin/sh',
          'TEST_ENV',
        );
        expect(result, equals('/bin/sh'));
      });

      test('throws if path does not exist', () async {
        expect(
          () => resolveExecutableOverridePath('/nonexistent/path', 'TEST_ENV'),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.toolMissing),
            ),
          ),
        );
      });

      test('returns null for null/empty input', () async {
        final result = await resolveExecutableOverridePath(null, 'TEST_ENV');
        expect(result, isNull);
      });

      test('throws for relative path', () {
        expect(
          () => resolveExecutableOverridePath('relative/path', 'TEST_ENV'),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.invalidArgs),
            ),
          ),
        );
      });
    });

    group('resolveFileOverridePath', () {
      test('returns path if valid file exists', () async {
        // Use /etc/passwd which should exist on Unix
        final result = await resolveFileOverridePath('/etc/passwd', 'TEST_ENV');
        expect(result, equals('/etc/passwd'));
      });

      test('throws if path does not exist', () async {
        expect(
          () => resolveFileOverridePath('/nonexistent/file', 'TEST_ENV'),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.toolMissing),
            ),
          ),
        );
      });

      test('returns null for null/empty input', () async {
        final result = await resolveFileOverridePath(null, 'TEST_ENV');
        expect(result, isNull);
      });
    });

    group('error details', () {
      test('COMMAND_FAILED includes stdout, stderr, exitCode', () async {
        try {
          await runCmd('sh', ['-c', 'echo out && echo err >&2 && exit 5']);
          fail('should throw');
        } on AppError catch (e) {
          expect(e.code, equals(AppErrorCodes.commandFailed));
          expect(e.details?['stdout'], contains('out'));
          expect(e.details?['stderr'], contains('err'));
          expect(e.details?['exitCode'], equals(5));
        }
      });

      test('timeout error includes timeoutMs in details', () async {
        try {
          await runCmd('sleep', ['10'], const ExecOptions(timeoutMs: 200));
          fail('should throw');
        } on AppError catch (e) {
          expect(e.code, equals(AppErrorCodes.commandFailed));
          expect(e.message, contains('timed out'));
          expect(e.details?['timeoutMs'], equals(200));
        }
      });
    });

    group('edge cases', () {
      test('empty command arguments', () async {
        final result = await runCmd('echo', []);
        expect(result.exitCode, equals(0));
      });

      test('handles commands with spaces in arguments', () async {
        final result = await runCmd('echo', ['hello world']);
        expect(result.stdout.trim(), equals('hello world'));
      });

      test('rejects invalid executable command', () {
        expect(
          () => runCmd('../path/to/cmd', []),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.invalidArgs),
            ),
          ),
        );
      });
    });
  });
}
