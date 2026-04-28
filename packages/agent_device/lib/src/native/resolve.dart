library;

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Resolve a native asset bundled with the agent_device package.
///
/// Tries three resolution strategies in order:
/// 1. Package URI — works for `dart run` and `dart pub global activate`
/// 2. Exe-relative — works for compiled binaries (Homebrew, standalone)
/// 3. Repo-root walk — works for local development
///
/// Returns null if the asset can't be found through any strategy.
Future<String?> resolveNativeAsset(String relativePath) async {
  return await _fromPackageUri(relativePath) ??
      _fromExeRelative(relativePath) ??
      _fromRepoRoot(relativePath);
}

/// Resolve the directory containing a native asset group.
/// [group] is e.g. 'android-snapshot-helper' or 'ios-runner'.
Future<String?> resolveNativeAssetDir(String group) async {
  return await _dirFromPackageUri(group) ??
      _dirFromExeRelative(group) ??
      _dirFromRepoRoot(group);
}

// ---------------------------------------------------------------------------
// Strategy 1: Isolate.resolvePackageUri (dart run / pub global activate)
// ---------------------------------------------------------------------------

Future<String?> _fromPackageUri(String relativePath) async {
  try {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:agent_device/src/native/$relativePath'),
    );
    if (uri == null) return null;
    final file = File.fromUri(uri);
    return file.existsSync() ? file.path : null;
  } catch (_) {
    return null;
  }
}

Future<String?> _dirFromPackageUri(String group) async {
  try {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:agent_device/src/native/$group/'),
    );
    if (uri == null) return null;
    final dir = Directory.fromUri(uri);
    return dir.existsSync() ? dir.path : null;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Strategy 2: exe-relative (compiled binary / Homebrew)
// Expects: <prefix>/bin/ad → <prefix>/share/agent-device/<relativePath>
// ---------------------------------------------------------------------------

String? _fromExeRelative(String relativePath) {
  try {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final shareFile = File(
      p.join(exeDir.parent.path, 'share', 'agent-device', relativePath),
    );
    if (shareFile.existsSync()) return shareFile.path;
    // Also check libexec/ (alternative Homebrew layout)
    final libexecFile = File(
      p.join(exeDir.parent.path, 'libexec', 'agent-device', relativePath),
    );
    if (libexecFile.existsSync()) return libexecFile.path;
    return null;
  } catch (_) {
    return null;
  }
}

String? _dirFromExeRelative(String group) {
  try {
    final exeDir = File(Platform.resolvedExecutable).parent;
    for (final sub in ['share', 'libexec']) {
      final dir = Directory(
        p.join(exeDir.parent.path, sub, 'agent-device', group),
      );
      if (dir.existsSync()) return dir.path;
    }
    return null;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Strategy 3: walk up from CWD / script to find repo root
// ---------------------------------------------------------------------------

String? _fromRepoRoot(String relativePath) {
  final root = _findRepoRoot();
  if (root == null) return null;
  // Check lib/src/native/ first (package layout)
  final inLib = File(
    p.join(root, 'packages', 'agent_device', 'lib', 'src', 'native', relativePath),
  );
  if (inLib.existsSync()) return inLib.path;
  // Check top-level (repo development layout)
  final topLevel = File(p.join(root, relativePath));
  if (topLevel.existsSync()) return topLevel.path;
  return null;
}

String? _dirFromRepoRoot(String group) {
  final root = _findRepoRoot();
  if (root == null) return null;
  final inLib = Directory(
    p.join(root, 'packages', 'agent_device', 'lib', 'src', 'native', group),
  );
  if (inLib.existsSync()) return inLib.path;
  final topLevel = Directory(p.join(root, group));
  if (topLevel.existsSync()) return topLevel.path;
  return null;
}

String? _findRepoRoot() {
  for (final start in _candidateStartDirs()) {
    var dir = start;
    for (var i = 0; i < 10; i++) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  return null;
}

Iterable<Directory> _candidateStartDirs() sync* {
  yield Directory.current;
  try {
    yield Directory(p.dirname(Platform.resolvedExecutable));
  } catch (_) {}
  try {
    yield Directory(p.dirname(Platform.script.toFilePath()));
  } catch (_) {}
}
