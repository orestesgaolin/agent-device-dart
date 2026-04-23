library;

import 'package:agent_device/src/utils/errors.dart';

import '../base_command.dart';

class SnapshotCommand extends AgentDeviceCommand {
  SnapshotCommand() {
    argParser
      ..addFlag(
        'interactive',
        abbr: 'i',
        help: 'Only include interactive nodes (default: full tree).',
        negatable: false,
      )
      ..addFlag(
        'compact',
        abbr: 'c',
        help: 'Prune group-only nodes.',
        negatable: false,
      )
      ..addOption('depth', abbr: 'd', help: 'Max tree depth.')
      ..addOption('scope', abbr: 's', help: 'Scope to a specific ref.')
      ..addFlag(
        'raw',
        help: 'Return raw snapshot (no filtering / shaping).',
        negatable: false,
      );
  }

  @override
  String get name => 'snapshot';

  @override
  String get description => 'Capture a snapshot of the current screen.';

  @override
  Future<int> run() async {
    final depthRaw = argResults?['depth'] as String?;
    final depth = depthRaw == null ? null : int.tryParse(depthRaw);
    if (depthRaw != null && depth == null) {
      throw AppError(AppErrorCodes.invalidArgs, '--depth must be an integer.');
    }
    final device = await openAgentDevice();
    try {
      final snap = await device.snapshot(
        interactiveOnly: (argResults?['interactive'] as bool?) ?? false
            ? true
            : null,
        compact: (argResults?['compact'] as bool?) ?? false ? true : null,
        depth: depth,
        scope: argResults?['scope'] as String?,
        raw: (argResults?['raw'] as bool?) ?? false ? true : null,
      );
      final data = <String, Object?>{
        'deviceSerial': device.device.id,
        'nodeCount': (snap.nodes ?? const []).length,
        'rawNodeCount': snap.analysis?.rawNodeCount,
        'maxDepth': snap.analysis?.maxDepth,
        'truncated': snap.truncated,
      };
      emitResult(
        data,
        humanFormat: (d) =>
            'snapshot: ${data['nodeCount']} visible nodes, '
            'raw=${data['rawNodeCount']}, depth=${data['maxDepth']}',
      );
      return 0;
    } finally {
      // Deliberately don't close the session — subsequent CLI calls (e.g.
      // `tap`, `fill`) reuse the same session. `close` command is explicit.
    }
  }
}
