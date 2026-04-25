// Port of agent-device/src/platforms/ios/install-artifact.ts (path
// sources only — URL sources, archive extraction, and download
// validation are deferred until there's a concrete need).
//
// Resolves a user-supplied `.app` directory or `.ipa` file into a
// concrete `installablePath` plus extracted bundle metadata
// (CFBundleIdentifier + CFBundleDisplayName/Name from Info.plist),
// unzipping `.ipa` archives into a tmpdir along the way. Returns a
// cleanup callback so callers can drop the tmpdir after install.
library;

import 'dart:io';

import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';
import 'package:path/path.dart' as p;

/// Resolved iOS install artifact. [installablePath] is either the
/// caller's `.app` bundle directory or the `.app` extracted out of an
/// `.ipa` archive. [archivePath] is the original `.ipa` path when the
/// caller passed one (otherwise null). [cleanup] removes any tmpdir
/// created during preparation; safe to call repeatedly.
class PreparedIosInstallArtifact {
  final String? archivePath;
  final String installablePath;
  final String? bundleId;
  final String? appName;
  final Future<void> Function() cleanup;

  PreparedIosInstallArtifact({
    this.archivePath,
    required this.installablePath,
    this.bundleId,
    this.appName,
    required this.cleanup,
  });
}

/// Options for [prepareIosInstallArtifact].
class PrepareIosInstallArtifactOptions {
  /// Optional bundle id or bundle name hint used to disambiguate a
  /// multi-app `.ipa`. When the archive contains exactly one `.app`
  /// the hint is ignored.
  final String? appIdentifierHint;
  const PrepareIosInstallArtifactOptions({this.appIdentifierHint});
}

/// Prepare [path] for `xcrun simctl install` / `devicectl device
/// install app`. Accepts either a `.app` directory or a `.ipa` file.
/// Throws [AppError] with [AppErrorCodes.invalidArgs] for malformed
/// input.
Future<PreparedIosInstallArtifact> prepareIosInstallArtifact(
  String path, {
  PrepareIosInstallArtifactOptions options = const PrepareIosInstallArtifactOptions(),
}) async {
  final lower = path.toLowerCase();
  final stat = await FileSystemEntity.type(path);
  if (stat == FileSystemEntityType.notFound) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'iOS install source not found: $path',
    );
  }
  if (stat == FileSystemEntityType.directory && lower.endsWith('.app')) {
    final info = await readIosBundleInfo(path);
    return PreparedIosInstallArtifact(
      installablePath: path,
      bundleId: info.bundleId,
      appName: info.appName,
      cleanup: () async {},
    );
  }
  if (stat == FileSystemEntityType.file && lower.endsWith('.ipa')) {
    return _resolveIpa(path, options);
  }
  throw AppError(
    AppErrorCodes.invalidArgs,
    'Expected an iOS .app directory or .ipa file, got: $path',
  );
}

/// One `.app` bundle inside an `.ipa`'s `Payload/` directory.
class _IosPayloadAppBundle {
  final String installPath;
  final String bundleName;
  String? bundleId;
  String? appName;
  _IosPayloadAppBundle({
    required this.installPath,
    required this.bundleName,
  });
}

Future<PreparedIosInstallArtifact> _resolveIpa(
  String ipaPath,
  PrepareIosInstallArtifactOptions options,
) async {
  final tempDir = await Directory.systemTemp.createTemp('ad-ios-ipa-');
  Future<void> cleanup() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  try {
    final unzip = await runCmd('unzip', [
      '-q',
      ipaPath,
      '-d',
      tempDir.path,
    ], const ExecOptions(allowFailure: true, timeoutMs: 60000));
    if (unzip.exitCode != 0) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid IPA: unzip failed (exit ${unzip.exitCode})',
        details: {'stderr': unzip.stderr, 'path': ipaPath},
      );
    }
    final payloadDir = Directory(p.join(tempDir.path, 'Payload'));
    if (!await payloadDir.exists()) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid IPA: missing Payload directory',
        details: {'path': ipaPath},
      );
    }
    final bundles = <_IosPayloadAppBundle>[];
    await for (final entry in payloadDir.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      if (!name.toLowerCase().endsWith('.app')) continue;
      bundles.add(
        _IosPayloadAppBundle(
          installPath: entry.path,
          bundleName: name.replaceAll(RegExp(r'\.app$', caseSensitive: false), ''),
        ),
      );
    }
    if (bundles.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid IPA: expected at least one .app under Payload, found 0',
        details: {'path': ipaPath},
      );
    }

    if (bundles.length == 1) {
      final info = await readIosBundleInfo(bundles[0].installPath);
      return PreparedIosInstallArtifact(
        archivePath: ipaPath,
        installablePath: bundles[0].installPath,
        bundleId: info.bundleId,
        appName: info.appName,
        cleanup: cleanup,
      );
    }

    // Multi-app .ipa: backfill bundle metadata for every payload entry,
    // then resolve via the caller's hint.
    await Future.wait(bundles.map((b) async {
      final info = await readIosBundleInfo(b.installPath);
      b.bundleId = info.bundleId;
      b.appName = info.appName;
    }));
    final hint = options.appIdentifierHint?.trim();
    if (hint == null || hint.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid IPA: found ${bundles.length} .app bundles under Payload. '
        'Pass an app identifier or bundle name matching one of: '
        '${bundles.map(_formatBundleDetails).join(', ')}',
      );
    }
    final resolved = _resolveBundleByHint(bundles, hint);
    if (resolved == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid IPA: found ${bundles.length} .app bundles under Payload '
        'and none matched "$hint". Available bundles: '
        '${bundles.map(_formatBundleDetails).join(', ')}',
      );
    }
    return PreparedIosInstallArtifact(
      archivePath: ipaPath,
      installablePath: resolved.installPath,
      bundleId: resolved.bundleId,
      appName: resolved.appName,
      cleanup: cleanup,
    );
  } catch (_) {
    await cleanup();
    rethrow;
  }
}

_IosPayloadAppBundle? _resolveBundleByHint(
  List<_IosPayloadAppBundle> bundles,
  String hint,
) {
  final lower = hint.toLowerCase();
  // Prefer an exact bundle-name match (the directory name minus `.app`).
  final byName = bundles
      .where((b) => b.bundleName.toLowerCase() == lower)
      .toList();
  if (byName.length == 1) return byName.single;
  if (byName.length > 1) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Invalid IPA: multiple app bundles matched "$hint" by name. '
      'Use a bundle id hint instead.',
    );
  }
  if (hint.contains('.')) {
    final byId = bundles
        .where((b) => b.bundleId?.toLowerCase() == lower)
        .toList();
    if (byId.length == 1) return byId.single;
  }
  return null;
}

String _formatBundleDetails(_IosPayloadAppBundle b) {
  final identity = b.bundleId ?? b.appName;
  return identity != null
      ? '${b.bundleName}.app ($identity)'
      : '${b.bundleName}.app';
}

/// Bundle metadata extracted from `Info.plist`. Both fields are
/// optional because plutil may legitimately not surface them on
/// malformed bundles.
class IosBundleInfo {
  final String? bundleId;
  final String? appName;
  const IosBundleInfo({this.bundleId, this.appName});
}

/// Read `CFBundleIdentifier` + `CFBundleDisplayName`/`CFBundleName`
/// from `<appBundlePath>/Info.plist` via `plutil -extract`. Returns
/// nulls for missing keys; throws if the plist itself can't be read.
Future<IosBundleInfo> readIosBundleInfo(String appBundlePath) async {
  final infoPlist = p.join(appBundlePath, 'Info.plist');
  if (!await File(infoPlist).exists()) {
    return const IosBundleInfo();
  }
  final bundleId = await _readInfoPlistString(infoPlist, 'CFBundleIdentifier');
  final displayName = await _readInfoPlistString(infoPlist, 'CFBundleDisplayName');
  final bundleName = await _readInfoPlistString(infoPlist, 'CFBundleName');
  return IosBundleInfo(
    bundleId: bundleId,
    appName: displayName ?? bundleName,
  );
}

Future<String?> _readInfoPlistString(String plistPath, String key) async {
  final r = await runCmd('plutil', [
    '-extract',
    key,
    'raw',
    '-o',
    '-',
    plistPath,
  ], const ExecOptions(allowFailure: true, timeoutMs: 10000));
  if (r.exitCode != 0) return null;
  final value = r.stdout.trim();
  return value.isEmpty ? null : value;
}
