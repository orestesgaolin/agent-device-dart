// Dart-only: disk-backed [CommandSessionStore].
//
// The TypeScript `SessionStore` (src/daemon/session-store.ts) is a purely
// in-memory `Map<string, SessionState>` — TS gets cross-invocation session
// sharing through its long-lived daemon process, not from a file-backed
// store. The Dart port's Phase 6A ships file-backed storage as a bridge so
// cross-invocation sharing works before the daemon (Phase 6B) lands.
// Phase 6B will reuse this store inside the daemon process.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'contract.dart';

/// Stores [CommandSessionRecord]s as one JSON file per session under
/// `<sessionsDir>/<safeName>.json`.
///
/// Atomicity: [set] writes to a `.tmp` sibling and atomically renames over
/// the final path, so partial writes cannot be read.
///
/// Concurrency: each mutation acquires an exclusive advisory lock on a
/// `.lock` sidecar via [RandomAccessFile.lock]. Advisory locking is
/// cooperative — only processes using this class respect it, which is the
/// only thing we care about in practice.
class FileSessionStore implements CommandSessionStore {
  final String sessionsDir;

  FileSessionStore(this.sessionsDir);

  @override
  Future<CommandSessionRecord?> get(String name) async {
    final file = _fileFor(name);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return CommandSessionRecord.fromJson(<String, Object?>{
        for (final e in decoded.entries) e.key.toString(): e.value,
      });
    } on FormatException {
      // Corrupt file — treat as absent rather than crashing the caller.
      return null;
    }
  }

  @override
  Future<void> set(CommandSessionRecord record) async {
    await _ensureDir();
    final file = _fileFor(record.name);
    // Each writer uses a unique tmp name — pid + random bits — so racing
    // processes don't clobber each other's rename source.
    final tmp = File('${file.path}.tmp.${pid}_${_randomHex(8)}');
    await _withLock(record.name, () async {
      final bytes = utf8.encode('${jsonEncode(record.toJson())}\n');
      try {
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(file.path);
      } catch (_) {
        // Clean up an orphaned tmp on failure so repeated failures don't
        // leak files.
        if (await tmp.exists()) {
          try {
            await tmp.delete();
          } catch (_) {}
        }
        rethrow;
      }
    });
  }

  static final Random _rng = Random.secure();

  static String _randomHex(int bytes) {
    final sb = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      sb.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  @override
  Future<void> delete(String name) async {
    final file = _fileFor(name);
    await _withLock(name, () async {
      if (await file.exists()) {
        await file.delete();
      }
      final tmp = File('${file.path}.tmp');
      if (await tmp.exists()) {
        await tmp.delete();
      }
    });
  }

  @override
  Future<List<CommandSessionRecord>> list() async {
    final dir = Directory(sessionsDir);
    if (!await dir.exists()) return const [];
    final entries = <CommandSessionRecord>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.json')) continue;
      if (name.endsWith('.tmp.json') || name.endsWith('.lock.json')) continue;
      try {
        final raw = await entity.readAsString();
        if (raw.trim().isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        entries.add(
          CommandSessionRecord.fromJson(<String, Object?>{
            for (final e in decoded.entries) e.key.toString(): e.value,
          }),
        );
      } on FormatException {
        // Skip corrupt files silently; `get` behaves the same way.
        continue;
      }
    }
    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  Future<void> _ensureDir() async {
    final dir = Directory(sessionsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  File _fileFor(String name) =>
      File(p.join(sessionsDir, '${_safeName(name)}.json'));

  File _lockFileFor(String name) =>
      File(p.join(sessionsDir, '${_safeName(name)}.lock'));

  /// Acquire an advisory exclusive lock on the per-session `.lock` file and
  /// run [body]. Cross-process-safe on all platforms Dart supports.
  Future<T> _withLock<T>(String name, Future<T> Function() body) async {
    await _ensureDir();
    final lock = _lockFileFor(name);
    if (!await lock.exists()) await lock.create();
    final handle = await lock.open(mode: FileMode.write);
    try {
      await handle.lock(FileLock.exclusive);
      try {
        return await body();
      } finally {
        await handle.unlock();
      }
    } finally {
      await handle.close();
    }
  }

  /// Session names come from user input (`--session`) and the final
  /// filename shouldn't allow directory traversal or weird characters.
  /// Mirrors `SessionStore.safeSessionName` in the TS source.
  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
}
