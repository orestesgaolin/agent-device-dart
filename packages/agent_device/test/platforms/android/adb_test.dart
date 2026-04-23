/// Tests for adb.dart — ADB binary path resolution and device arguments.
library;

import 'package:agent_device/src/platforms/android/adb.dart';
import 'package:test/test.dart';

void main() {
  group('adbArgs', () {
    test('builds adb command arguments with serial', () {
      final args = adbArgs('emulator-5554', [
        'shell',
        'getprop',
        'ro.build.version.release',
      ]);
      expect(
        args,
        equals([
          '-s',
          'emulator-5554',
          'shell',
          'getprop',
          'ro.build.version.release',
        ]),
      );
    });

    test('handles empty args list', () {
      final args = adbArgs('device-123', []);
      expect(args, equals(['-s', 'device-123']));
    });

    test('preserves arg order', () {
      final args = adbArgs('serial-xyz', ['devices', '-l', 'extra']);
      expect(args, equals(['-s', 'serial-xyz', 'devices', '-l', 'extra']));
    });
  });

  group('isClipboardShellUnsupported', () {
    test('detects "no shell command implementation" error', () {
      const stdout = 'error: adb exited with exit code 1';
      const stderr =
          'cmd: Can\'t find service: clipboard_manager (no shell command implementation)';
      expect(isClipboardShellUnsupported(stdout, stderr), isTrue);
    });

    test('detects "unknown command" error', () {
      const stdout = '';
      const stderr = 'adb: Unknown command: "clip"';
      expect(isClipboardShellUnsupported(stdout, stderr), isTrue);
    });

    test('case-insensitive detection', () {
      const stdout = 'ERROR: NO SHELL COMMAND IMPLEMENTATION';
      const stderr = '';
      expect(isClipboardShellUnsupported(stdout, stderr), isTrue);
    });

    test('returns false for normal output', () {
      const stdout = 'com.example.app';
      const stderr = '';
      expect(isClipboardShellUnsupported(stdout, stderr), isFalse);
    });

    test('returns false for success output', () {
      const stdout = 'clipboard set';
      const stderr = '';
      expect(isClipboardShellUnsupported(stdout, stderr), isFalse);
    });

    test('checks both stdout and stderr', () {
      const stdout = 'Some output';
      const stderr = 'unknown command somewhere in here';
      expect(isClipboardShellUnsupported(stdout, stderr), isTrue);
    });
  });
}
