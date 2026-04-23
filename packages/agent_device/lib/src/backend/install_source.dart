// Port of agent-device/src/backend.ts
library;

import 'options.dart';

// ============================================================================
// Installation Operations
// ============================================================================

/// Target for installing an app.
class BackendInstallTarget {
  final String? app;
  final BackendInstallSource source;

  const BackendInstallTarget({this.app, required this.source});

  Map<String, Object?> toJson() => <String, Object?>{
    if (app != null) 'app': app,
    'source': _installSourceToJson(source),
  };
}

Map<String, Object?> _installSourceToJson(BackendInstallSource source) {
  if (source is BackendInstallSourcePath) {
    return {'kind': 'path', 'path': source.path};
  } else if (source is BackendInstallSourceUploadedArtifact) {
    return {'kind': 'uploadedArtifact', 'id': source.id};
  } else if (source is BackendInstallSourceUrl) {
    return {'kind': 'url', 'url': source.url};
  }
  throw StateError('Unknown install source type: $source');
}

/// Result of an install operation.
class BackendInstallResult {
  final String? appId;
  final String? appName;
  final String? bundleId;
  final String? packageName;
  final String? launchTarget;
  final String? installablePath;
  final String? archivePath;
  final Map<String, Object?> extra;

  const BackendInstallResult({
    this.appId,
    this.appName,
    this.bundleId,
    this.packageName,
    this.launchTarget,
    this.installablePath,
    this.archivePath,
    this.extra = const {},
  });

  Map<String, Object?> toJson() => <String, Object?>{
    ...extra,
    if (appId != null) 'appId': appId,
    if (appName != null) 'appName': appName,
    if (bundleId != null) 'bundleId': bundleId,
    if (packageName != null) 'packageName': packageName,
    if (launchTarget != null) 'launchTarget': launchTarget,
    if (installablePath != null) 'installablePath': installablePath,
    if (archivePath != null) 'archivePath': archivePath,
  };
}

// ============================================================================
// Simulator Lifecycle
// ============================================================================

/// Options for ensuring a simulator exists and is ready.
class BackendEnsureSimulatorOptions {
  final String device;
  final String? runtime;
  final bool? boot;
  final bool? reuseExisting;

  const BackendEnsureSimulatorOptions({
    required this.device,
    this.runtime,
    this.boot,
    this.reuseExisting,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'device': device,
    if (runtime != null) 'runtime': runtime,
    if (boot != null) 'boot': boot,
    if (reuseExisting != null) 'reuseExisting': reuseExisting,
  };
}

/// Result of ensuring a simulator.
class BackendEnsureSimulatorResult {
  final String udid;
  final String device;
  final String runtime;
  final bool created;
  final bool booted;
  final String? simulatorSetPath;

  const BackendEnsureSimulatorResult({
    required this.udid,
    required this.device,
    required this.runtime,
    required this.created,
    required this.booted,
    this.simulatorSetPath,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'udid': udid,
    'device': device,
    'runtime': runtime,
    'created': created,
    'booted': booted,
    if (simulatorSetPath != null) 'simulatorSetPath': simulatorSetPath,
  };
}
