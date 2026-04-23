// Port of agent-device/src/core/open-target.ts

const String iosSafariBundleId = 'com.apple.mobilesafari';

/// Returns true if [input] looks like a deep link (scheme://...).
bool isDeepLinkTarget(String input) {
  final value = input.trim();
  if (value.isEmpty) return false;
  if (RegExp(r'\s').hasMatch(value)) return false;

  final match = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*):(.+)$').firstMatch(value);
  if (match == null) return false;

  final scheme = (match.group(1) ?? '').toLowerCase();
  final rest = match.group(2) ?? '';

  switch (scheme) {
    case 'http' || 'https' || 'ws' || 'wss' || 'ftp' || 'ftps':
      return rest.startsWith('//');
    default:
      return true;
  }
}

/// Returns true if [input] is an HTTP(S) URL.
bool isWebUrl(String input) {
  final scheme = (input.trim().split(':').firstOrNull ?? '').toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

/// Resolves the bundle ID for opening [url] on iOS.
///
/// If [appBundleId] is provided, returns it. Otherwise, if [url] is a web URL,
/// returns the Safari bundle ID. Returns null if neither condition applies.
String? resolveIosDeviceDeepLinkBundleId(String? appBundleId, String url) {
  final bundleId = appBundleId?.trim();
  if (bundleId != null && bundleId.isNotEmpty) return bundleId;
  if (isWebUrl(url)) return iosSafariBundleId;
  return null;
}
