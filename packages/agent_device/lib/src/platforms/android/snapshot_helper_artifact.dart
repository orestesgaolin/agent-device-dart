// Port of agent-device/src/platforms/android/snapshot-helper-artifact.ts
//
// Deviations from upstream:
// - Remote manifest fetch (`prepareAndroidSnapshotHelperArtifactFromManifestUrl`)
//   is omitted. The Dart port always uses the locally bundled APK under
//   `android-snapshot-helper/dist/` (mirrors how the iOS runner is resolved).
// - SHA-256 verification (`verifyAndroidSnapshotHelperArtifact`) and manifest
//   parsing (`parseAndroidSnapshotHelperManifest`) are ported 1:1.

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/utils/exec.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../utils/errors.dart';
import 'snapshot_helper_types.dart';

const _allowedInstallFlags = {'-r', '-t', '-d', '-g'};

/// Verify the APK checksum against the manifest's sha256 field.
///
/// Throws [AppError] with code `COMMAND_FAILED` if the hashes differ.
Future<void> verifyAndroidSnapshotHelperArtifact(
  AndroidSnapshotHelperArtifact artifact,
) async {
  final actual = await _sha256File(artifact.apkPath);
  if (actual != artifact.manifest.sha256) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Android snapshot helper APK checksum mismatch',
      details: {
        'apkPath': artifact.apkPath,
        'expectedSha256': artifact.manifest.sha256,
        'actualSha256': actual,
      },
    );
  }
}

/// Parse a raw JSON-decoded object into an [AndroidSnapshotHelperManifest].
///
/// Throws [AppError] with code `INVALID_ARGS` for any malformed field.
AndroidSnapshotHelperManifest parseAndroidSnapshotHelperManifest(
  Object? value,
) {
  if (value == null || value is! Map) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Android snapshot helper manifest must be an object.',
    );
  }
  final record = value.cast<String, Object?>();
  return AndroidSnapshotHelperManifest(
    name: _readLiteral(record['name'], 'name', androidSnapshotHelperName),
    version: _readString(record['version'], 'version'),
    releaseTag: _readOptionalString(record['releaseTag']),
    assetName: _readOptionalString(record['assetName']),
    apkUrl: _readOptionalNullableString(record['apkUrl'], 'apkUrl'),
    sha256: _readSha256(record['sha256']),
    checksumName: _readOptionalString(record['checksumName']),
    packageName: _readString(record['packageName'], 'packageName'),
    versionCode: _readNumber(record['versionCode'], 'versionCode'),
    instrumentationRunner: _readString(
      record['instrumentationRunner'],
      'instrumentationRunner',
    ),
    minSdk: _readNumber(record['minSdk'], 'minSdk'),
    targetSdk: record.containsKey('targetSdk') && record['targetSdk'] != null
        ? _readNumber(record['targetSdk'], 'targetSdk')
        : null,
    outputFormat: _readLiteral(
      record['outputFormat'],
      'outputFormat',
      androidSnapshotHelperOutputFormat,
    ),
    statusProtocol: _readLiteral(
      record['statusProtocol'],
      'statusProtocol',
      androidSnapshotHelperProtocol,
    ),
    installArgs: _readAndroidSnapshotHelperManifestInstallArgs(record['installArgs']),
  );
}

/// Extract the validated `adb install` args from the manifest.
List<String> readAndroidSnapshotHelperInstallArgs(
  AndroidSnapshotHelperManifest manifest,
) {
  return _readAndroidSnapshotHelperManifestInstallArgs(manifest.installArgs);
}

/// Resolve the bundled APK artifact from `android-snapshot-helper/dist/`
/// relative to the repo root.
///
/// Walks up the directory tree from this file's package root to find the
/// `android-snapshot-helper/dist/` directory, reads the manifest JSON, then
/// returns a resolved artifact.
///
/// Returns `null` if no bundled APK is found — callers fall back to
/// uiautomator dump.
Future<AndroidSnapshotHelperArtifact?> resolveBundledAndroidSnapshotHelperArtifact() async {
  final repoRoot = _findRepoRoot();
  if (repoRoot == null) return null;

  final helperDir = p.join(repoRoot, 'android-snapshot-helper', 'dist');

  var artifact = _readBundledArtifact(helperDir);
  if (artifact != null) return artifact;

  // Auto-build: if the source exists but dist doesn't, build + package.
  final buildScript = p.join(repoRoot, 'scripts', 'build-android-snapshot-helper.sh');
  final packageScript = File(
    p.join(repoRoot, 'agent-device', 'scripts', 'package-android-snapshot-helper.sh'),
  );
  final helperSource = Directory(p.join(repoRoot, 'android-snapshot-helper', 'src'));
  if (!helperSource.existsSync()) return null;
  if (!File(buildScript).existsSync() && !packageScript.existsSync()) return null;

  final sdkRoot = Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  if (sdkRoot == null || sdkRoot.isEmpty) return null;

  try {
    stderr.writeln('[snapshot] auto-building Android snapshot helper APK…');
    if (packageScript.existsSync()) {
      final r = await runCmd('sh', [
        packageScript.path, '0.0.1', 'local', helperDir,
      ], const ExecOptions(allowFailure: true));
      if (r.exitCode != 0) {
        stderr.writeln('[snapshot] helper build failed (exit ${r.exitCode})');
        return null;
      }
    } else {
      final r = await runCmd('sh', [
        buildScript, '0.0.1', helperDir,
      ], const ExecOptions(allowFailure: true));
      if (r.exitCode != 0) {
        stderr.writeln('[snapshot] helper build failed (exit ${r.exitCode})');
        return null;
      }
    }
    stderr.writeln('[snapshot] helper build complete');
  } catch (_) {
    return null;
  }

  return _readBundledArtifact(helperDir);
}

AndroidSnapshotHelperArtifact? _readBundledArtifact(String helperDir) {
  Directory distDir;
  try {
    distDir = Directory(helperDir);
    if (!distDir.existsSync()) return null;
  } catch (_) {
    return null;
  }

  try {
    final manifestFiles = distDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).endsWith('.manifest.json'))
        .toList();

    if (manifestFiles.isEmpty) return null;

    final manifestFile = manifestFiles.first;
    final rawJson = manifestFile.readAsStringSync();
    final manifest = parseAndroidSnapshotHelperManifest(
      jsonDecode(rawJson),
    );

    final apkName =
        manifest.assetName ??
        'agent-device-android-snapshot-helper-${manifest.version}.apk';
    final apkPath = p.join(helperDir, apkName);

    if (!File(apkPath).existsSync()) return null;

    return AndroidSnapshotHelperArtifact(
      apkPath: apkPath,
      manifest: manifest,
    );
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

String? _findRepoRoot() {
  // Walk up from the current working directory looking for a `pubspec.yaml`
  // that is at the repo workspace root (contains `android-snapshot-helper/`).
  var dir = Directory.current;
  for (var i = 0; i < 10; i++) {
    if (Directory(p.join(dir.path, 'android-snapshot-helper')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

Future<String> _sha256File(String filePath) async {
  final input = File(filePath).openRead();
  final digest = await sha256.bind(input).first;
  return digest.toString();
}

List<String> _readAndroidSnapshotHelperManifestInstallArgs(Object? value) {
  final installArgs = _readStringArray(value, 'installArgs');
  if (installArgs.isEmpty || installArgs[0] != 'install') {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Android snapshot helper manifest installArgs must start with "install".',
    );
  }
  if (installArgs.any((arg) => arg.contains('\x00'))) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Android snapshot helper manifest installArgs must not contain null bytes.',
    );
  }
  final unsupported = installArgs.skip(1).where((arg) => !_allowedInstallFlags.contains(arg));
  if (unsupported.isNotEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Android snapshot helper manifest installArgs contains unsupported install flag "${unsupported.first}".',
    );
  }
  return installArgs;
}

String _readSha256(Object? value) {
  final raw = _readString(value, 'sha256').trim().toLowerCase();
  if (raw.length != 64 || !_isLowerHex(raw)) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Android snapshot helper manifest sha256 must be a 64-character hex string.',
    );
  }
  return raw;
}

String _readString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Android snapshot helper manifest $field is required.',
    );
  }
  return value;
}

String? _readOptionalString(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value;
  return null;
}

String? _readOptionalNullableString(Object? value, String field) {
  if (value == null) return null;
  return _readString(value, field);
}

int _readNumber(Object? value, String field) {
  if (value is! num || value != value.truncate()) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Android snapshot helper manifest $field must be an integer.',
    );
  }
  return value.toInt();
}

String _readLiteral(Object? value, String field, String expected) {
  if (value != expected) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Android snapshot helper manifest $field must be "$expected".',
    );
  }
  return expected;
}

List<String> _readStringArray(Object? value, String field) {
  if (value is! List || !value.every((e) => e is String)) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Android snapshot helper manifest $field must be a string array.',
    );
  }
  return List<String>.from(value);
}

bool _isLowerHex(String value) {
  for (final char in value.runes) {
    final isDigit = char >= 0x30 && char <= 0x39;
    final isLowerHexLetter = char >= 0x61 && char <= 0x66;
    if (!isDigit && !isLowerHexLetter) return false;
  }
  return true;
}
