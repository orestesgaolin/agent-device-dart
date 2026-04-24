// `agent-device logs` — three modes:
//   - default: one-shot dump of recent device logs filtered to the open
//     app (iOS via `xcrun simctl spawn log show`, Android via
//     `adb logcat -d -T <time>`).
//   - `--stream --out <path>`: start a background tail into <path>. The
//     PID is persisted so a later invocation can stop it.
//   - `--stop`: stop the currently-running stream for this device and
//     report final byte count.
library;

import 'dart:io';

import 'package:agent_device/src/utils/errors.dart';

import '../base_command.dart';

class LogsCommand extends AgentDeviceCommand {
  LogsCommand() {
    argParser
      ..addOption(
        'since',
        help:
            'One-shot mode: time window to include. Relative forms like `30s` / `5m` / `1h` '
            'pass through as `--last`; anything else is forwarded to '
            '`log show --start` (e.g. `@<epoch>` or `YYYY-MM-DD HH:MM:SS`). '
            'Default: last 5m.',
      )
      ..addOption(
        'limit',
        help:
            'One-shot mode: cap the number of returned log lines (keeps the tail).',
      )
      ..addOption(
        'out',
        help:
            'Write the raw log text to this file (one-shot mode) or stream '
            'output to this file (--stream mode). In one-shot mode without '
            '--out, the text lands on stdout.',
      )
      ..addFlag(
        'stream',
        negatable: false,
        help:
            'Start a detached background log tail writing to --out. The '
            'PID is persisted so a later `logs --stop` invocation (from '
            'any shell) can close it.',
      )
      ..addFlag(
        'stop',
        negatable: false,
        help:
            'Stop the currently-running background log stream for this '
            'device and report the final file size.',
      );
  }

  @override
  String get name => 'logs';

  @override
  String get description =>
      'Dump or stream device logs for the current app. Default: one-shot '
      'dump. Use --stream/--stop for long-running tails.';

  @override
  Future<int> run() async {
    final wantStream = argResults?['stream'] == true;
    final wantStop = argResults?['stop'] == true;
    if (wantStream && wantStop) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        '--stream and --stop are mutually exclusive.',
      );
    }

    final device = await openAgentDevice();

    if (wantStop) {
      final res = await device.stopLogStream();
      emitResult(
        res.toJson(),
        humanFormat: (_) {
          final mb = (res.bytes ?? 0) / (1024 * 1024);
          return 'stopped log stream → ${res.outPath} '
              '(${res.bytes ?? 0} bytes${mb >= 0.01 ? ', ${mb.toStringAsFixed(2)} MB' : ''})'
              '${res.stale == true ? '  [pid was already gone]' : ''}';
        },
      );
      return 0;
    }

    if (wantStream) {
      final outPath = argResults?['out'] as String?;
      if (outPath == null || outPath.isEmpty) {
        throw AppError(
          AppErrorCodes.invalidArgs,
          '--stream requires --out <path>.',
        );
      }
      final res = await device.startLogStream(outPath);
      emitResult(
        res.toJson(),
        humanFormat: (_) =>
            'streaming logs → ${res.outPath} (pid ${res.hostPid ?? '?'}). '
            'Stop with `agent-device logs --stop`.',
      );
      return 0;
    }

    // One-shot dump.
    final since = argResults?['since'] as String?;
    final limit = int.tryParse(argResults?['limit'] as String? ?? '');
    final outPath = argResults?['out'] as String?;
    final res = await device.readLogs(since: since, limit: limit);

    final text = res.entries.map((e) => e.message).join('\n');
    if (outPath != null) {
      final out = File(outPath);
      await out.parent.create(recursive: true);
      await out.writeAsString(text.isEmpty ? '' : '$text\n');
    }

    if (asJson) {
      emitResult({
        'entries': res.entries.length,
        'backend': res.backend,
        if (outPath != null) 'outPath': outPath,
      });
      return 0;
    }
    if (outPath != null) {
      stdout.writeln(
        'wrote ${res.entries.length} lines → $outPath '
        '(${res.backend ?? 'unknown-backend'})',
      );
    } else {
      stdout.writeln(text);
    }
    return 0;
  }
}
