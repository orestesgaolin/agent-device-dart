// `agent-device logs` — dump recent device logs filtered to the open
// app. Phase 10: iOS simulator only (via `xcrun simctl spawn log show`).
// Android wires up once the logcat one-shot path lands.
library;

import 'dart:io';

import '../base_command.dart';

class LogsCommand extends AgentDeviceCommand {
  LogsCommand() {
    argParser
      ..addOption(
        'since',
        help:
            'Time window to include. Relative forms like `30s` / `5m` / `1h` '
            'pass through as `--last`; anything else is forwarded to '
            '`log show --start` (e.g. `@<epoch>` or `YYYY-MM-DD HH:MM:SS`). '
            'Default: last 5m.',
      )
      ..addOption(
        'limit',
        help: 'Cap the number of returned log lines (keeps the tail).',
      )
      ..addOption(
        'out',
        help:
            'Write the raw log text to this file instead of stdout. '
            'The JSON envelope still reports the count.',
      );
  }

  @override
  String get name => 'logs';

  @override
  String get description =>
      'Dump recent device logs for the current app (iOS simulator only).';

  @override
  Future<int> run() async {
    final since = argResults?['since'] as String?;
    final limit = int.tryParse(argResults?['limit'] as String? ?? '');
    final outPath = argResults?['out'] as String?;
    final device = await openAgentDevice();
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
