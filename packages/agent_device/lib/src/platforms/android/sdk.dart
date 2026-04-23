/// Port of agent-device/src/platforms/android/sdk.ts.
///
/// Android SDK path resolution. Searches ANDROID_SDK_ROOT, ANDROID_HOME,
/// and ~/Android/Sdk in order. Detects subdirectories (emulator, platform-tools,
/// cmdline-tools) and prepends them to PATH for downstream adb/emulator lookup.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

const List<String> _androidSdkBinDirs = [
  'emulator',
  'platform-tools',
  'cmdline-tools/latest/bin',
  'cmdline-tools/tools/bin',
];

/// Unique, non-empty list from input strings (preserves order, dedupes).
List<String> _uniqueNonEmpty(List<String> values) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && !seen.contains(trimmed)) {
      seen.add(trimmed);
      normalized.add(trimmed);
    }
  }
  return normalized;
}

/// Resolve potential Android SDK roots from environment.
///
/// Checks (in order):
/// 1. ANDROID_SDK_ROOT
/// 2. ANDROID_HOME
/// 3. ~/Android/Sdk (fallback default)
///
/// Returns non-empty strings in order, deduped.
List<String> resolveAndroidSdkRoots([Map<String, String>? env]) {
  env ??= Platform.environment;
  final configuredRoot = env['ANDROID_SDK_ROOT']?.trim();
  final configuredHome = env['ANDROID_HOME']?.trim();
  final homeDir = env['HOME']?.trim() ?? Platform.environment['HOME'] ?? '';
  final defaultRoot = homeDir.isNotEmpty
      ? p.join(homeDir, 'Android', 'Sdk')
      : '';

  return _uniqueNonEmpty([
    if (configuredRoot != null && configuredRoot.isNotEmpty) configuredRoot,
    if (configuredHome != null && configuredHome.isNotEmpty) configuredHome,
    if (defaultRoot.isNotEmpty) defaultRoot,
  ]);
}

/// Check if a candidate path exists and is executable (directory).
Future<bool> _pathExists(String candidate) async {
  try {
    final stat = await FileStat.stat(candidate);
    return stat.type == FileSystemEntityType.directory;
  } catch (_) {
    return false;
  }
}

/// Configure PATH and env vars for Android SDK.
///
/// Searches for SDK root directories (from ANDROID_SDK_ROOT, ANDROID_HOME,
/// ~/Android/Sdk) and looks for known bin directories within them
/// (emulator, platform-tools, cmdline-tools/latest/bin, cmdline-tools/tools/bin).
///
/// If any are found, sets ANDROID_SDK_ROOT and ANDROID_HOME to the first
/// detected root, and prepends all found bin dirs to PATH.
///
/// Modifies the provided env map in-place (or Platform.environment if not provided).
Future<void> ensureAndroidSdkPathConfigured([Map<String, String>? env]) async {
  env ??= Platform.environment;

  final existingDirs = <String>[];
  String? detectedRoot;

  for (final sdkRoot in resolveAndroidSdkRoots(env)) {
    final presentDirs = <String>[];
    for (final relativeDir in _androidSdkBinDirs) {
      final candidate = p.join(sdkRoot, relativeDir);
      if (await _pathExists(candidate)) {
        presentDirs.add(candidate);
      }
    }

    if (presentDirs.isEmpty) continue;

    detectedRoot ??= sdkRoot;
    existingDirs.addAll(presentDirs);
  }

  // Set SDK root env vars if detected and not already set.
  if (detectedRoot != null) {
    env['ANDROID_SDK_ROOT'] = env['ANDROID_SDK_ROOT']?.trim() ?? detectedRoot;
    env['ANDROID_HOME'] = env['ANDROID_HOME']?.trim() ?? detectedRoot;
  }

  // Prepend discovered bin dirs to PATH.
  if (existingDirs.isEmpty) return;

  final pathDelimiter = Platform.isWindows ? ';' : ':';
  final currentEntries = (env['PATH'] ?? '')
      .split(pathDelimiter)
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();

  env['PATH'] = _uniqueNonEmpty([
    ...existingDirs,
    ...currentEntries,
  ]).join(pathDelimiter);
}
