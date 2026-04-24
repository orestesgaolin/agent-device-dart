// `agent-device network <logPath>` — extract HTTP activity from an
// existing app-log dump. Pairs with `agent-device logs --out <path>`:
//
//   agent-device logs --out /tmp/app.log --since 2m --platform ios ...
//   agent-device network /tmp/app.log --backend ios-simulator --json
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/diagnostics/network_log.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:args/command_runner.dart';

import 'simple_action_cmds.dart' show jsonish;

class NetworkCommand extends Command<int> {
  NetworkCommand() {
    argParser
      ..addOption(
        'backend',
        help:
            'Backend that produced the log (affects Android cross-line '
            'enrichment). One of: ios-simulator, ios-device, android, macos.',
        allowed: const ['ios-simulator', 'ios-device', 'android', 'macos'],
      )
      ..addOption(
        'include',
        help:
            'How much of each entry to include. summary (default) / headers / '
            'body / all.',
        allowed: const ['summary', 'headers', 'body', 'all'],
        defaultsTo: 'summary',
      )
      ..addOption(
        'max-entries',
        help: 'Cap the number of returned entries (1-200). Default 25.',
      )
      ..addOption(
        'max-payload-chars',
        help:
            'Per-field character cap for raw / headers / body (64-16384). '
            'Default 2048.',
      )
      ..addOption(
        'max-scan-lines',
        help:
            'Cap on the tail of the log file to scan (100-20000). '
            'Default 4000.',
      )
      ..addFlag('json', help: 'Emit JSON output.', negatable: false);
  }

  @override
  String get name => 'network';

  @override
  String get description =>
      'Extract recent HTTP request/response activity from an app-log dump.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const [];
    if (rest.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'network requires a <logPath> argument (an app-log file captured via '
        '`agent-device logs --out <path>`).',
      );
    }
    final logPath = rest.first;
    final backend = NetworkLogBackend.parse(argResults?['backend'] as String?);
    final include = NetworkIncludeMode.parse(argResults?['include'] as String?);
    final maxEntries = int.tryParse(
      argResults?['max-entries'] as String? ?? '',
    );
    final maxPayloadChars = int.tryParse(
      argResults?['max-payload-chars'] as String? ?? '',
    );
    final maxScanLines = int.tryParse(
      argResults?['max-scan-lines'] as String? ?? '',
    );
    final asJson =
        argResults?['json'] == true ||
        (globalResults?['json'] as bool? ?? false);

    final dump = readRecentNetworkTraffic(
      logPath,
      backend: backend,
      include: include,
      maxEntries: maxEntries,
      maxPayloadChars: maxPayloadChars,
      maxScanLines: maxScanLines,
    );

    if (asJson) {
      stdout.writeln(jsonEncode({'success': true, 'data': dump.toJson()}));
      return 0;
    }
    if (!dump.exists) {
      stdout.writeln('(log file not found: $logPath)');
      return 0;
    }
    if (dump.entries.isEmpty) {
      stdout.writeln(
        'no network activity found in ${dump.scannedLines} scanned lines',
      );
      return 0;
    }
    final buf = StringBuffer()
      ..writeln(
        '${dump.matchedLines} entries from ${dump.scannedLines} lines '
        '(include=${dump.include.value})',
      );
    for (final e in dump.entries) {
      buf.write('${e.method ?? '?'} ${e.status ?? '?'} ${e.url}');
      if (e.durationMs != null) buf.write('  ${e.durationMs}ms');
      if (e.timestamp != null) buf.write('  @${e.timestamp}');
      buf.writeln();
      if (e.headers != null) buf.writeln('  headers: ${jsonish(e.headers!)}');
      if (e.requestBody != null) {
        buf.writeln('  requestBody: ${jsonish(e.requestBody!)}');
      }
      if (e.responseBody != null) {
        buf.writeln('  responseBody: ${jsonish(e.responseBody!)}');
      }
    }
    stdout.write(buf.toString());
    return 0;
  }
}
