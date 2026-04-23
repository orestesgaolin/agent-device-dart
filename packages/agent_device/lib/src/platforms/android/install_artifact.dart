/// Port of agent-device/src/platforms/android/install-artifact.ts.
///
/// Android APK/AAB artifact validation and package name extraction.
/// TODO(port): depends on install-source.ts (Wave C), currently stubbed.
library;

import 'package:path/path.dart' as p;

import 'manifest.dart';

/// Prepared artifact ready for installation on an Android device.
class PreparedAndroidInstallArtifact {
  /// Path to extracted archive if source was a zip/tar (e.g. extracted APK from AAB).
  final String? archivePath;

  /// Path to the installable file (.apk or .aab).
  final String installablePath;

  /// Package name extracted from manifest, if resolution was requested.
  final String? packageName;

  /// Cleanup function to remove temporary files (e.g. extracted archive).
  final Future<void> Function() cleanup;

  PreparedAndroidInstallArtifact({
    this.archivePath,
    required this.installablePath,
    this.packageName,
    required this.cleanup,
  });
}

/// Prepare an Android install artifact.
///
/// Validates that the source is an APK or AAB file, optionally extracts the
/// package name from the manifest if [resolveIdentity] is true.
///
/// TODO(port): The TS source depends on [materializeInstallablePath] from
/// install-source.ts which handles URL downloads, archive extraction, etc.
/// For now, this stub assumes [source] is a local path. Proper implementation
/// deferred to Wave C when install-source.ts is ported.
Future<PreparedAndroidInstallArtifact> prepareAndroidInstallArtifact(
  String source, {
  bool resolveIdentity = true,
}) async {
  // TODO(port): Full implementation requires materializeInstallablePath from Wave C.
  // For now, assume source is a direct file path.
  if (!_isAndroidInstallablePath(source)) {
    throw ArgumentError(
      'Expected Android installable (.apk or .aab), got: $source',
    );
  }

  String? packageName;
  if (resolveIdentity) {
    packageName = await resolveAndroidArchivePackageName(source);
  }

  return PreparedAndroidInstallArtifact(
    installablePath: source,
    packageName: packageName,
    cleanup: () async {
      // No cleanup for direct file paths.
    },
  );
}

/// Check if a file path is a valid Android installable (.apk or .aab).
bool _isAndroidInstallablePath(String candidatePath) {
  final extension = p.extension(candidatePath).toLowerCase();
  return extension == '.apk' || extension == '.aab';
}
