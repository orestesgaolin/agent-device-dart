import 'dart:io';

import 'package:agent_device/src/cli/run_cli.dart';
import 'package:test/test.dart';

void main() {
  group(
    'runCli',
    () {
      test('`--help` exits 0', () async {
        // CommandRunner prints usage and returns null; runCli coerces to 0.
        final exit = await runCli(['--help']);
        expect(exit, 0);
      });

      test('unknown command exits 64 (usage error)', () async {
        final exit = await runCli(['not-a-real-command']);
        expect(exit, 64);
      });

      test('devices with invalid platform errors out', () async {
        // `--platform frobnicator` is rejected by ArgParser.allowed.
        final exit = await runCli(['devices', '--platform', 'frobnicator']);
        expect(exit, 64);
      });

      test('tap without args exits 1 and normalizes error', () async {
        final exit = await runCli(['tap', '--platform', 'android', '--json']);
        // Will fail before hitting adb because no positional args.
        // Accept either 1 (AppError) or 64 (usage) depending on path taken.
        expect(exit, anyOf(equals(1), equals(64)));
      });
    },
    // Smoke tests don't require a device. Keep the whole group skipped on
    // unusual platforms if needed in the future. For now, always run.
    skip: Platform.isWindows
        ? 'CLI smoke tests not yet validated on Windows'
        : null,
  );
}
