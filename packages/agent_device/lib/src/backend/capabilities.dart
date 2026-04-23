// Port of agent-device/src/backend.ts
library;

/// Known backend capability names that may be reported by a backend.
enum BackendCapabilityName {
  androidShell('android.shell'),
  iosRunnerCommand('ios.runnerCommand'),
  macosDesktopScreenshot('macos.desktopScreenshot');

  final String value;

  const BackendCapabilityName(this.value);

  /// Parse from a string value. Returns null if the value is not recognized.
  static BackendCapabilityName? fromString(String? value) {
    return switch (value) {
      'android.shell' => BackendCapabilityName.androidShell,
      'ios.runnerCommand' => BackendCapabilityName.iosRunnerCommand,
      'macos.desktopScreenshot' => BackendCapabilityName.macosDesktopScreenshot,
      _ => null,
    };
  }

  @override
  String toString() => value;
}

/// A set of capability names that a backend reports as supported.
typedef BackendCapabilitySet = List<BackendCapabilityName>;
