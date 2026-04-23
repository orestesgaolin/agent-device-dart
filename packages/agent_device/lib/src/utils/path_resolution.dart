// Port of `agent-device/src/utils/path-resolution.ts`.
//
// Utilities for home directory and path resolution with support for
// environment variable overrides and relative path expansion.
library;

import 'dart:io' show Directory, Platform;
import 'package:path/path.dart' as p;

typedef EnvMap = Map<String, String?>;

/// Options for path resolution.
class PathResolutionOptions {
  final String? cwd;
  final EnvMap? env;

  PathResolutionOptions({this.cwd, this.env});
}

/// Resolves the home directory from the environment.
///
/// On Unix-like systems, uses the `HOME` environment variable if present,
/// otherwise falls back to `Platform.environment['HOME']`.
/// On Windows, uses `USERPROFILE`.
String resolveHomeDirectory([EnvMap? env]) {
  final envOrDefault = env ?? Platform.environment;
  if (Platform.isWindows) {
    return envOrDefault['USERPROFILE']?.trim() ?? '';
  }
  return envOrDefault['HOME']?.trim() ?? '';
}

/// Expands the tilde (`~`) prefix in a path to the user's home directory.
///
/// - If [inputPath] is exactly `~`, returns the home directory.
/// - If [inputPath] starts with `~/`, replaces `~/` with the home directory.
/// - Otherwise, returns [inputPath] unchanged.
String expandUserHomePath(String inputPath, [PathResolutionOptions? options]) {
  options ??= PathResolutionOptions();
  if (inputPath == '~') return resolveHomeDirectory(options.env);
  if (inputPath.startsWith('~/')) {
    return p.join(resolveHomeDirectory(options.env), inputPath.substring(2));
  }
  return inputPath;
}

/// Resolves a user-provided path to an absolute path.
///
/// First expands `~` using [expandUserHomePath]. If the result is relative,
/// resolves it relative to [options.cwd] (or the current directory if not set).
String resolveUserPath(String inputPath, [PathResolutionOptions? options]) {
  options ??= PathResolutionOptions();
  final expandedPath = expandUserHomePath(inputPath, options);
  if (p.isAbsolute(expandedPath)) return expandedPath;
  final baseDir = options.cwd ?? Directory.current.path;
  return p.absolute(baseDir, expandedPath);
}
