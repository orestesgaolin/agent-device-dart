// Port of agent-device/src/backend.ts
library;

/// Supported platform identifiers for backend implementations.
enum AgentDeviceBackendPlatform {
  ios,
  android,
  macos,
  linux;

  /// The string representation used in wire formats.
  String get value {
    return switch (this) {
      AgentDeviceBackendPlatform.ios => 'ios',
      AgentDeviceBackendPlatform.android => 'android',
      AgentDeviceBackendPlatform.macos => 'macos',
      AgentDeviceBackendPlatform.linux => 'linux',
    };
  }

  /// Parse from a string value. Returns null if the value is not recognized.
  static AgentDeviceBackendPlatform? fromString(String? value) {
    return switch (value) {
      'ios' => AgentDeviceBackendPlatform.ios,
      'android' => AgentDeviceBackendPlatform.android,
      'macos' => AgentDeviceBackendPlatform.macos,
      'linux' => AgentDeviceBackendPlatform.linux,
      _ => null,
    };
  }

  @override
  String toString() => value;
}
