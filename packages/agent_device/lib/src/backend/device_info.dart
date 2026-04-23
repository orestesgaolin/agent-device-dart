// Port of agent-device/src/backend.ts
library;

import 'platform.dart';

/// Possible device orientations.
enum BackendDeviceOrientation {
  portrait('portrait'),
  portraitUpsideDown('portrait-upside-down'),
  landscapeLeft('landscape-left'),
  landscapeRight('landscape-right');

  final String value;

  const BackendDeviceOrientation(this.value);

  static BackendDeviceOrientation? fromString(String? value) {
    return switch (value) {
      'portrait' => BackendDeviceOrientation.portrait,
      'portrait-upside-down' => BackendDeviceOrientation.portraitUpsideDown,
      'landscape-left' => BackendDeviceOrientation.landscapeLeft,
      'landscape-right' => BackendDeviceOrientation.landscapeRight,
      _ => null,
    };
  }

  @override
  String toString() => value;
}

/// Filter criteria for querying available devices.
class BackendDeviceFilter {
  final AgentDeviceBackendPlatform? platform;
  final String? target;
  final String? kind;

  const BackendDeviceFilter({this.platform, this.target, this.kind});
}

/// Information about a specific device that a backend can identify.
class BackendDeviceInfo {
  final String id;
  final String name;
  final AgentDeviceBackendPlatform platform;
  final String? target;
  final String? kind;
  final bool? booted;
  final Map<String, Object?>? details;

  const BackendDeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    this.target,
    this.kind,
    this.booted,
    this.details,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'platform': platform.value,
    if (target != null) 'target': target,
    if (kind != null) 'kind': kind,
    if (booted != null) 'booted': booted,
    if (details != null) 'details': details,
  };
}

/// A target device specification for operations like boot or ensure-simulator.
class BackendDeviceTarget {
  final String? id;
  final String? name;
  final AgentDeviceBackendPlatform? platform;
  final String? target;
  final bool? headless;

  const BackendDeviceTarget({
    this.id,
    this.name,
    this.platform,
    this.target,
    this.headless,
  });
}

/// Filter for app listing.
enum BackendAppListFilter {
  all('all'),
  userInstalled('user-installed');

  final String value;

  const BackendAppListFilter(this.value);

  static BackendAppListFilter? fromString(String? value) {
    return switch (value) {
      'all' => BackendAppListFilter.all,
      'user-installed' => BackendAppListFilter.userInstalled,
      _ => null,
    };
  }

  @override
  String toString() => value;
}

/// Information about a single installed application.
class BackendAppInfo {
  final String id;
  final String? name;
  final String? bundleId;
  final String? packageName;
  final String? activity;

  const BackendAppInfo({
    required this.id,
    this.name,
    this.bundleId,
    this.packageName,
    this.activity,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (name != null) 'name': name,
    if (bundleId != null) 'bundleId': bundleId,
    if (packageName != null) 'packageName': packageName,
    if (activity != null) 'activity': activity,
  };
}

/// Current state of an application on the device.
class BackendAppState {
  final String? appId;
  final String? bundleId;
  final String? packageName;
  final String? activity;
  final String? state;
  final Map<String, Object?>? details;

  const BackendAppState({
    this.appId,
    this.bundleId,
    this.packageName,
    this.activity,
    this.state,
    this.details,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    if (appId != null) 'appId': appId,
    if (bundleId != null) 'bundleId': bundleId,
    if (packageName != null) 'packageName': packageName,
    if (activity != null) 'activity': activity,
    if (state != null) 'state': state,
    if (details != null) 'details': details,
  };
}

/// Event that can be triggered on an app.
class BackendAppEvent {
  final String name;
  final Map<String, Object?>? payload;

  const BackendAppEvent({required this.name, this.payload});

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (payload != null) 'payload': payload,
  };
}
