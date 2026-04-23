/// Port of `agent-device/src/utils/device.ts` — platform enum and helpers.
library;

/// Known platform targets. Mirror of TypeScript's `Platform | 'apple'`.
enum PlatformSelector { ios, android, macos, linux, apple }

/// Convert a [PlatformSelector] to its string representation.
String platformSelectorToString(PlatformSelector platform) {
  switch (platform) {
    case PlatformSelector.ios:
      return 'ios';
    case PlatformSelector.android:
      return 'android';
    case PlatformSelector.macos:
      return 'macos';
    case PlatformSelector.linux:
      return 'linux';
    case PlatformSelector.apple:
      return 'apple';
  }
}

/// Parse a string to [PlatformSelector], or null if not recognized.
PlatformSelector? parsePlatformSelector(String? value) {
  switch (value) {
    case 'ios':
      return PlatformSelector.ios;
    case 'android':
      return PlatformSelector.android;
    case 'macos':
      return PlatformSelector.macos;
    case 'linux':
      return PlatformSelector.linux;
    case 'apple':
      return PlatformSelector.apple;
    default:
      return null;
  }
}

/// True if the platform is an Apple platform (iOS or macOS).
bool isApplePlatform(PlatformSelector platform) {
  return platform == PlatformSelector.ios || platform == PlatformSelector.macos;
}
