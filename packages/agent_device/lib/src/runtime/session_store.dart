// Port of agent-device/src/runtime.ts::createMemorySessionStore
library;

import 'contract.dart';

/// In-memory implementation of [CommandSessionStore]. Sessions live only for
/// the lifetime of the store — callers that want persistence across process
/// restarts should use a disk-backed store (not yet ported; Phase 6).
class MemorySessionStore implements CommandSessionStore {
  final Map<String, CommandSessionRecord> _records;

  MemorySessionStore([Iterable<CommandSessionRecord> initial = const []])
    : _records = {for (final r in initial) r.name: r};

  @override
  Future<CommandSessionRecord?> get(String name) async => _records[name];

  @override
  Future<void> set(CommandSessionRecord record) async {
    _records[record.name] = record;
  }

  @override
  Future<void> delete(String name) async {
    _records.remove(name);
  }

  @override
  Future<List<CommandSessionRecord>> list() async =>
      List.unmodifiable(_records.values);
}

/// Convenience factory mirroring the TS `createMemorySessionStore`.
CommandSessionStore createMemorySessionStore([
  Iterable<CommandSessionRecord> initial = const [],
]) => MemorySessionStore(initial);
