library;

import 'package:agent_device/src/snapshot/snapshot.dart';
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
    final snap = await device.snapshot(
      interactiveOnly: (argResults?['interactive'] as bool?) ?? false
          ? true
          : null,
      compact: (argResults?['compact'] as bool?) ?? false ? true : null,
      depth: depth,
      scope: argResults?['scope'] as String?,
      raw: (argResults?['raw'] as bool?) ?? false ? true : null,
    );

    final rawNodes = snap.nodes ?? const [];
    final nodes = rawNodes.whereType<SnapshotNode>().toList();

    final data = <String, Object?>{
      'deviceSerial': device.device.id,
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'nodeCount': nodes.length,
      'rawNodeCount': snap.analysis?.rawNodeCount,
      'maxDepth': snap.analysis?.maxDepth,
      'truncated': snap.truncated,
    };
    emitResult(
      data,
      humanFormat: (_) {
        if (nodes.isEmpty) return '(empty snapshot)';
        final buf = StringBuffer();
        for (final n in nodes) {
          final indent = '  ' * (n.depth ?? 0);
          final tag = n.type ?? n.role ?? '?';
          final text = n.label ?? n.value ?? n.identifier ?? '';
          final refTag = '@${n.ref}';
          buf.writeln('$indent$refTag  $tag  ${text.isNotEmpty ? '"$text"' : ''}');
        }
        buf.writeln(
          '--- ${nodes.length} nodes, '
          'raw=${snap.analysis?.rawNodeCount}, '
          'depth=${snap.analysis?.maxDepth}',
        );
        return buf.toString().trimRight();
      },
    );
    return 0;
  }
}
