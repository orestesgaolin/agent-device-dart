library;

import 'package:args/command_runner.dart';

import '../base_command.dart';

class SessionCommand extends Command<int> {
  SessionCommand() {
    addSubcommand(SessionListCommand());
    addSubcommand(SessionShowCommand());
    addSubcommand(SessionClearCommand());
  }

  @override
  String get name => 'session';

  @override
  String get description => 'Inspect and manage persisted session records.';
}

class SessionListCommand extends AgentDeviceCommand {
  @override
  String get name => 'list';

  @override
  String get description =>
      'List all persisted sessions under the state directory.';

  @override
  Future<int> run() async {
    final store = resolveSessionStore();
    final records = await store.list();
    emitResult(
      records.map((r) => r.toJson()).toList(),
      humanFormat: (_) {
        if (records.isEmpty) return '(no sessions)';
        final buf = StringBuffer();
        for (final r in records) {
          buf.writeln(
            '${r.name.padRight(16)}  '
            'device=${r.deviceSerial ?? '-'}  '
            'app=${r.appId ?? '-'}',
          );
        }
        return buf.toString().trimRight();
      },
    );
    return 0;
  }
}

class SessionShowCommand extends AgentDeviceCommand {
  @override
  String get name => 'show';

  @override
  String get description =>
      'Print a single session record. Uses --session (default: "default") '
      'or a positional name.';

  @override
  Future<int> run() async {
    final name = positionals.isEmpty ? sessionName : positionals.first;
    final store = resolveSessionStore();
    final record = await store.get(name);
    if (record == null) {
      emitResult(null, humanFormat: (_) => 'session "$name" not found');
      return 0;
    }
    emitResult(
      record.toJson(),
      humanFormat: (_) {
        final buf = StringBuffer()..writeln('name: ${record.name}');
        if (record.deviceSerial != null) {
          buf.writeln('deviceSerial: ${record.deviceSerial}');
        }
        if (record.appId != null) buf.writeln('appId: ${record.appId}');
        if (record.appBundleId != null) {
          buf.writeln('appBundleId: ${record.appBundleId}');
        }
        if (record.appName != null) buf.writeln('appName: ${record.appName}');
        if (record.backendSessionId != null) {
          buf.writeln('backendSessionId: ${record.backendSessionId}');
        }
        if (record.metadata != null) {
          buf.writeln('metadata: ${record.metadata}');
        }
        return buf.toString().trimRight();
      },
    );
    return 0;
  }
}

class SessionClearCommand extends AgentDeviceCommand {
  SessionClearCommand() {
    argParser.addFlag(
      'all',
      help: 'Clear every persisted session.',
      negatable: false,
    );
  }

  @override
  String get name => 'clear';

  @override
  String get description =>
      'Delete a session record (or all with --all). Does not kill any '
      'running apps on the device.';

  @override
  Future<int> run() async {
    final store = resolveSessionStore();
    final all = (argResults?['all'] as bool?) ?? false;
    if (all) {
      final records = await store.list();
      for (final r in records) {
        await store.delete(r.name);
      }
      emitResult(
        {'cleared': records.map((r) => r.name).toList()},
        humanFormat: (_) =>
            'cleared ${records.length} session${records.length == 1 ? '' : 's'}',
      );
      return 0;
    }
    final name = positionals.isEmpty ? sessionName : positionals.first;
    await store.delete(name);
    emitResult({
      'cleared': [name],
    }, humanFormat: (_) => 'cleared session "$name"');
    return 0;
  }
}
