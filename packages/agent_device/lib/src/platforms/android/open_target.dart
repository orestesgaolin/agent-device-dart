// Port of agent-device/src/platforms/android/open-target.ts

enum AndroidAppTargetKind {
  package('package'),
  binary('binary'),
  other('other');

  final String value;

  const AndroidAppTargetKind(this.value);

  @override
  String toString() => value;
}

final RegExp _androidBinaryTargetExtension = RegExp(
  r'\.(?:apk|aab)$',
  caseSensitive: false,
);
final RegExp _androidPackageNamePattern = RegExp(
  r'^[A-Za-z_][\w]*(\.[A-Za-z_][\w]*)+$',
);

/// Classifies an Android app target as a package name, binary path, or other.
AndroidAppTargetKind classifyAndroidAppTarget(String target) {
  final trimmed = target.trim();
  if (trimmed.isEmpty) return AndroidAppTargetKind.other;

  if (!_androidBinaryTargetExtension.hasMatch(trimmed)) {
    return _looksLikeAndroidPackageName(trimmed)
        ? AndroidAppTargetKind.package
        : AndroidAppTargetKind.other;
  }

  final looksLikePath =
      trimmed.contains('/') ||
      trimmed.contains('\\') ||
      trimmed.startsWith('.') ||
      trimmed.startsWith('~');

  if (looksLikePath || !_looksLikeAndroidPackageName(trimmed)) {
    return AndroidAppTargetKind.binary;
  }

  return AndroidAppTargetKind.package;
}

/// Returns true if [value] looks like an Android package name.
bool looksLikeAndroidPackageName(String value) {
  return _looksLikeAndroidPackageName(value);
}

bool _looksLikeAndroidPackageName(String value) {
  return _androidPackageNamePattern.hasMatch(value);
}

/// Formats an error message for when a non-package target is provided where
/// an installed package is required.
String formatAndroidInstalledPackageRequiredMessage(String target) {
  return 'Android runtime hints require an installed package name, not "$target". '
      'Install or reinstall the app first, then relaunch by package.';
}
