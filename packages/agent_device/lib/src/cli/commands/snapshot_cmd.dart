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
        final appId = snap.appBundleId;
        if (appId != null) {
          buf.writeln('Page: $appId');
          buf.writeln('App: $appId');
        }
        buf.writeln('Snapshot: ${nodes.length} nodes');
        for (final n in nodes) {
          final indent = '  ' * (n.depth ?? 0);
          final tag = _humanType(n.type ?? n.role ?? '?');
          final text = n.label ?? n.value ?? '';
          final id = n.identifier;
          final parts = [
            '$indent@${n.ref} [$tag]',
            if (text.isNotEmpty) '"$text"',
            if (id != null && id.isNotEmpty && id != text) 'id=$id',
          ];
          buf.writeln(parts.join(' '));
        }
        return buf.toString().trimRight();
      },
    );
    return 0;
  }
}

String _humanType(String raw) {
  const map = {
    'StaticText': 'text',
    'Application': 'application',
    'Window': 'window',
    'Button': 'button',
    'TextField': 'textfield',
    'Other': 'other',
    'Image': 'image',
    'Cell': 'cell',
    'Table': 'table',
    'ScrollView': 'scrollview',
    'NavigationBar': 'navbar',
    'TabBar': 'tabbar',
    'Switch': 'switch',
    'Slider': 'slider',
    'Link': 'link',
  };
  return map[raw] ?? raw.toLowerCase();
}
