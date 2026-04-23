// Port of agent-device/src/platforms/android/app-lifecycle.ts

import 'package:path/path.dart' as p;

import '../../utils/errors.dart';
import '../../utils/exec.dart';
import 'adb.dart';
import 'app_parsers.dart';
import 'devices.dart';
import 'install_artifact.dart';
import 'open_target.dart';

const String _androidLauncherCategory = 'android.intent.category.LAUNCHER';
const String _androidLeanbackCategory =
    'android.intent.category.LEANBACK_LAUNCHER';
const String _androidDefaultCategory = 'android.intent.category.DEFAULT';
const String _androidAppsDiscoveryHint =
    'Run agent-device apps --platform android to discover the installed package name, then retry open with that exact package.';
const String _androidAmbiguousAppHint =
    'Run agent-device apps --platform android to see the exact installed package names before retrying open.';

final Map<String, ({String type, String value})> _aliases = {
  'settings': (type: 'intent', value: 'android.settings.SETTINGS'),
};

/// Resolve an Android app target (package name or intent alias).
///
/// Classifies the input as a package name, intent alias, or falls back to
/// querying the device for matching packages via `pm list packages`.
/// Throws if multiple packages match or none are found.
Future<({String type, String value})> resolveAndroidApp(
  String deviceId,
  String app,
) async {
  final trimmed = app.trim();
  if (classifyAndroidAppTarget(trimmed) == AndroidAppTargetKind.package) {
    return (type: 'package', value: trimmed);
  }

  final alias = _aliases[trimmed.toLowerCase()];
  if (alias != null) {
    return alias;
  }

  final result = await runCmd(
    'adb',
    adbArgs(deviceId, ['shell', 'pm', 'list', 'packages']),
  );
  final packages = result.stdout
      .split('\n')
      .map((line) => line.replaceFirst('package:', '').trim())
      .where((line) => line.isNotEmpty)
      .toList();

  final matches = packages
      .where((pkg) => pkg.toLowerCase().contains(trimmed.toLowerCase()))
      .toList();

  if (matches.length == 1) {
    return (type: 'package', value: matches[0]);
  }

  if (matches.length > 1) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Multiple packages matched "$app"',
      details: {'matches': matches, 'hint': _androidAmbiguousAppHint},
    );
  }

  throw AppError(
    AppErrorCodes.appNotInstalled,
    'No package found matching "$app"',
    details: {'hint': _androidAppsDiscoveryHint},
  );
}

/// List installed apps on the device.
///
/// Returns packages that are launchable (have a LAUNCHER or LEANBACK_LAUNCHER
/// intent), optionally filtered to user-installed only. Results are sorted
/// alphabetically with inferred display names.
Future<List<({String package, String name})>> listAndroidApps(
  String deviceId, {
  String filter = 'all',
}) async {
  final launchable = await _listAndroidLaunchablePackages(deviceId);
  final List<String> packageIds;

  if (filter == 'user-installed') {
    final userInstalled = await _listAndroidUserInstalledPackages(deviceId);
    packageIds = userInstalled
        .where((pkg) => launchable.contains(pkg))
        .toList();
  } else {
    packageIds = launchable.toList();
  }

  final sorted = packageIds..sort();
  return sorted.map((pkg) {
    return (package: pkg, name: inferAndroidAppName(pkg));
  }).toList();
}

/// List launchable package names via intent query.
///
/// Queries the device for packages with LAUNCHER or LEANBACK_LAUNCHER
/// intents, depending on the device type (mobile vs TV).
Future<Set<String>> _listAndroidLaunchablePackages(String deviceId) async {
  final packages = <String>{};
  final categories = _resolveAndroidLaunchCategories(
    deviceId,
    includeFallback: true,
  );

  for (final category in categories) {
    final result = await runCmd(
      'adb',
      adbArgs(deviceId, [
        'shell',
        'cmd',
        'package',
        'query-activities',
        '--brief',
        '-a',
        'android.intent.action.MAIN',
        '-c',
        category,
      ]),
      const ExecOptions(allowFailure: true),
    );

    if (result.exitCode != 0 || result.stdout.trim().isEmpty) {
      continue;
    }

    for (final pkg in parseAndroidLaunchablePackages(result.stdout)) {
      packages.add(pkg);
    }
  }

  return packages;
}

/// Resolve the primary launcher category for the device type.
String _resolveAndroidLauncherCategory(String deviceId) {
  return _resolveAndroidLaunchCategories(deviceId).firstOrNull ??
      _androidLauncherCategory;
}

/// Resolve applicable launcher categories based on device type.
///
/// TVs use LEANBACK_LAUNCHER, phones use LAUNCHER. If device type is unknown
/// and [includeFallback] is true, returns both options.
List<String> _resolveAndroidLaunchCategories(
  String deviceId, {
  bool includeFallback = false,
}) {
  // TODO(port): Fetch device target from device info. For now, assume mobile.
  // When ported, check device.target == 'tv' vs 'mobile'.
  if (includeFallback) {
    return [_androidLauncherCategory, _androidLeanbackCategory];
  }
  return [_androidLauncherCategory];
}

/// List user-installed package names via pm list.
Future<List<String>> _listAndroidUserInstalledPackages(String deviceId) async {
  final result = await runCmd(
    'adb',
    adbArgs(deviceId, ['shell', 'pm', 'list', 'packages', '-3']),
  );
  return parseAndroidUserInstalledPackages(result.stdout);
}

/// Infer a display name from an Android package name.
///
/// Extracts the most significant token from the package name, removing
/// common generic prefixes (com, android, app, etc.). Splits on dots and
/// underscores, capitalizes each word, and joins with spaces.
String inferAndroidAppName(String packageName) {
  final ignoredTokens = {
    'com',
    'android',
    'google',
    'app',
    'apps',
    'service',
    'services',
    'mobile',
    'client',
  };

  final tokens = packageName
      .split('.')
      .expand((segment) => segment.split(RegExp(r'[_-]+')))
      .map((token) => token.trim().toLowerCase())
      .where((token) => token.isNotEmpty)
      .toList();

  if (tokens.isEmpty) return packageName;

  // Fallback to last token if all are ignored.
  String chosen = tokens.last;
  for (var i = tokens.length - 1; i >= 0; i--) {
    if (!ignoredTokens.contains(tokens[i])) {
      chosen = tokens[i];
      break;
    }
  }

  return chosen
      .split(RegExp(r'[^a-z0-9]+', caseSensitive: false))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

/// Get the currently foreground app on the device.
///
/// Tries multiple dumpsys commands to extract the focused window or activity.
/// Returns an [AndroidForegroundApp] with package and/or activity, or an
/// empty record if detection fails.
Future<AndroidForegroundApp> getAndroidAppState(String deviceId) async {
  final windowFocus = await _readAndroidFocus(deviceId, [
    ['shell', 'dumpsys', 'window', 'windows'],
    ['shell', 'dumpsys', 'window'],
  ]);
  if (windowFocus != null) return windowFocus;

  final activityFocus = await _readAndroidFocus(deviceId, [
    ['shell', 'dumpsys', 'activity', 'activities'],
    ['shell', 'dumpsys', 'activity'],
  ]);
  if (activityFocus != null) return activityFocus;

  return AndroidForegroundApp();
}

/// Try a sequence of dumpsys commands to extract foreground app.
///
/// Iterates through command argument lists, runs each, and returns the
/// first successfully parsed foreground app. Returns null if no command
/// produces a parseable result.
Future<AndroidForegroundApp?> _readAndroidFocus(
  String deviceId,
  List<List<String>> commands,
) async {
  for (final args in commands) {
    final result = await runCmd(
      'adb',
      adbArgs(deviceId, args),
      const ExecOptions(allowFailure: true),
    );
    final parsed = parseAndroidForegroundApp(result.stdout);
    if (parsed != null) return parsed;
  }
  return null;
}

/// Open an app or deep link on the device.
///
/// Handles deep link URLs, intent aliases, and package names. For package
/// names, resolves the launch activity via intent query. Ensures the device
/// is booted first. Throws if the app is not installed or activity cannot
/// be resolved.
Future<void> openAndroidApp(
  String deviceId,
  String app, {
  String? activity,
}) async {
  await waitForAndroidBoot(deviceId);

  final deepLinkTarget = app.trim();
  if (_isDeepLinkTarget(deepLinkTarget)) {
    if (activity != null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Activity override is not supported when opening a deep link URL',
      );
    }
    await runCmd(
      'adb',
      adbArgs(deviceId, [
        'shell',
        'am',
        'start',
        '-W',
        '-a',
        'android.intent.action.VIEW',
        '-d',
        deepLinkTarget,
      ]),
    );
    return;
  }

  final resolved = await resolveAndroidApp(deviceId, app);
  final launchCategory = _resolveAndroidLauncherCategory(deviceId);

  if (resolved.type == 'intent') {
    if (activity != null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Activity override requires a package name, not an intent',
      );
    }
    await runCmd(
      'adb',
      adbArgs(deviceId, ['shell', 'am', 'start', '-W', '-a', resolved.value]),
    );
    return;
  }

  // resolved.type == 'package'
  if (activity != null) {
    final component = activity.contains('/')
        ? activity
        : '${resolved.value}/${activity.startsWith('.') ? activity : '.$activity'}';
    try {
      await runCmd(
        'adb',
        adbArgs(deviceId, [
          'shell',
          'am',
          'start',
          '-W',
          '-a',
          'android.intent.action.MAIN',
          '-c',
          _androidDefaultCategory,
          '-c',
          launchCategory,
          '-n',
          component,
        ]),
      );
    } catch (error) {
      await _maybeRethrowAndroidMissingPackageError(
        deviceId,
        resolved.value,
        error,
      );
      rethrow;
    }
    return;
  }

  // No activity override: try primary launch first, then resolve component.
  final primaryResult = await runCmd(
    'adb',
    adbArgs(deviceId, [
      'shell',
      'am',
      'start',
      '-W',
      '-a',
      'android.intent.action.MAIN',
      '-c',
      _androidDefaultCategory,
      '-c',
      launchCategory,
      '-p',
      resolved.value,
    ]),
    const ExecOptions(allowFailure: true),
  );

  if (primaryResult.exitCode == 0 &&
      !isAmStartError(primaryResult.stdout, primaryResult.stderr)) {
    return;
  }

  final component = await _resolveAndroidLaunchComponent(
    deviceId,
    resolved.value,
  );
  if (component == null) {
    if (!(await _isAndroidPackageInstalled(deviceId, resolved.value))) {
      throw _buildAndroidPackageNotInstalledError(resolved.value);
    }
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to launch ${resolved.value}',
      details: {'stdout': primaryResult.stdout, 'stderr': primaryResult.stderr},
    );
  }

  await runCmd(
    'adb',
    adbArgs(deviceId, [
      'shell',
      'am',
      'start',
      '-W',
      '-a',
      'android.intent.action.MAIN',
      '-c',
      _androidDefaultCategory,
      '-c',
      launchCategory,
      '-n',
      component,
    ]),
  );
}

/// Check if a string looks like a deep link (URL).
bool _isDeepLinkTarget(String target) {
  return target.contains('://');
}

/// Build an error for a missing/not-installed package.
AppError _buildAndroidPackageNotInstalledError(String packageName) {
  return AppError(
    AppErrorCodes.appNotInstalled,
    'No package found matching "$packageName"',
    details: {'package': packageName, 'hint': _androidAppsDiscoveryHint},
  );
}

/// Check if a package is installed on the device.
///
/// Uses `pm path` to verify presence. Returns false on error or if the
/// package is not found.
Future<bool> _isAndroidPackageInstalled(
  String deviceId,
  String packageName,
) async {
  final result = await runCmd(
    'adb',
    adbArgs(deviceId, ['shell', 'pm', 'path', packageName]),
    const ExecOptions(allowFailure: true),
  );
  final output = '${result.stdout}\n${result.stderr}';

  if (result.exitCode == 0 &&
      output.contains(RegExp(r'\bpackage:', caseSensitive: false))) {
    return true;
  }

  if (_looksLikeMissingAndroidPackageOutput(output)) {
    return false;
  }

  return false;
}

/// Rethrow or replace an error if it indicates a missing package.
Future<void> _maybeRethrowAndroidMissingPackageError(
  String deviceId,
  String packageName,
  Object error,
) async {
  final output = error is AppError
      ? '${String.fromCharCode(0)}${String.fromCharCode(0)}'
      : '';
  if (_looksLikeMissingAndroidPackageOutput(output)) {
    throw _buildAndroidPackageNotInstalledError(packageName);
  }

  if (!(await _isAndroidPackageInstalled(deviceId, packageName))) {
    throw _buildAndroidPackageNotInstalledError(packageName);
  }
}

/// Check if a string matches patterns for missing/not-found package output.
bool _looksLikeMissingAndroidPackageOutput(String output) {
  return output.contains(
        RegExp(r'\bunknown package\b', caseSensitive: false),
      ) ||
      output.contains(
        RegExp(r'\bpackage .* (?:was|is) not found\b', caseSensitive: false),
      ) ||
      output.contains(
        RegExp(r'\bpackage .* does not exist\b', caseSensitive: false),
      ) ||
      output.contains(
        RegExp(r'\bcould not find package\b', caseSensitive: false),
      );
}

/// Resolve the launch component (package/activity) for a package name.
///
/// Queries the device for an activity matching the LAUNCHER intent category.
/// Returns the component string "package/activity" or null if none found.
Future<String?> _resolveAndroidLaunchComponent(
  String deviceId,
  String packageName,
) async {
  final categories = _resolveAndroidLaunchCategories(
    deviceId,
    includeFallback: true,
  ).toSet().toList();

  for (final category in categories) {
    final result = await runCmd(
      'adb',
      adbArgs(deviceId, [
        'shell',
        'cmd',
        'package',
        'resolve-activity',
        '--brief',
        '-a',
        'android.intent.action.MAIN',
        '-c',
        category,
        packageName,
      ]),
      const ExecOptions(allowFailure: true),
    );

    if (result.exitCode != 0) {
      continue;
    }

    final component = parseAndroidLaunchComponent(result.stdout);
    if (component != null) {
      return component;
    }
  }

  return null;
}

/// Check if `am start` output indicates a launch error.
bool isAmStartError(String stdout, String stderr) {
  final output = '$stdout\n$stderr';
  return output.contains(
    RegExp(
      r'Error:.*(?:Activity not started|unable to resolve Intent)',
      caseSensitive: false,
    ),
  );
}

/// Parse the launch component from resolved-activity output.
String? parseAndroidLaunchComponent(String stdout) {
  final lines = stdout
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  // Iterate backwards to find the last valid component line.
  for (var i = lines.length - 1; i >= 0; i--) {
    final line = lines[i];
    if (!line.contains('/')) continue;

    // Extract the first space-delimited token (the component).
    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.isNotEmpty) {
      return tokens[0];
    }
  }

  return null;
}

/// Open the device's home/default screen or launcher.
///
/// Waits for boot and returns without further action (the device is now
/// accessible for interaction).
Future<void> openAndroidDevice(String deviceId) async {
  await waitForAndroidBoot(deviceId);
}

/// Close an app (force-stop) on the device.
///
/// For 'settings', uses the system settings package name directly.
/// Otherwise resolves the app name and force-stops the package.
Future<void> closeAndroidApp(String deviceId, String app) async {
  final trimmed = app.trim();
  if (trimmed.toLowerCase() == 'settings') {
    await runCmd(
      'adb',
      adbArgs(deviceId, ['shell', 'am', 'force-stop', 'com.android.settings']),
    );
    return;
  }

  final resolved = await resolveAndroidApp(deviceId, app);
  if (resolved.type == 'intent') {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Close requires a package name, not an intent',
    );
  }

  await runCmd(
    'adb',
    adbArgs(deviceId, ['shell', 'am', 'force-stop', resolved.value]),
  );
}

/// Uninstall an app (package) from the device.
Future<({String package})> _uninstallAndroidApp(
  String deviceId,
  String app,
) async {
  final resolved = await resolveAndroidApp(deviceId, app);
  if (resolved.type == 'intent') {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'App uninstall requires a package name, not an intent',
    );
  }

  final result = await runCmd(
    'adb',
    adbArgs(deviceId, ['uninstall', resolved.value]),
    const ExecOptions(allowFailure: true),
  );

  if (result.exitCode != 0) {
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    if (!output.contains('unknown package') &&
        !output.contains('not installed')) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'adb uninstall failed for ${resolved.value}',
        details: {
          'stdout': result.stdout,
          'stderr': result.stderr,
          'exitCode': result.exitCode,
        },
      );
    }
  }

  return (package: resolved.value);
}

/// List installed packages before and after installation.
Future<Set<String>> _listInstalledAndroidPackages(String deviceId) async {
  final result = await runCmd(
    'adb',
    adbArgs(deviceId, ['shell', 'pm', 'list', 'packages']),
  );
  return {
    for (final line in result.stdout.split('\n'))
      line.replaceFirst('package:', '').trim(),
  }..removeWhere((p) => p.isEmpty);
}

/// Detect newly installed package by comparing before/after package lists.
Future<String?> _resolveInstalledAndroidPackageName(
  String deviceId,
  Set<String> beforePackages,
) async {
  final afterPackages = await _listInstalledAndroidPackages(deviceId);
  final installedNow = afterPackages
      .where((pkg) => !beforePackages.contains(pkg))
      .toList();

  return installedNow.length == 1 ? installedNow[0] : null;
}

/// Install an APK/AAB from a file path on the device.
///
/// Waits for boot, then calls bundletool for AAB or adb install for APK.
Future<void> installAndroidInstallablePath(
  String deviceId,
  String installablePath,
) async {
  await waitForAndroidBoot(deviceId);
  await _installAndroidAppFiles(deviceId, installablePath);
}

/// Install an app and optionally return the resolved package name.
///
/// If [packageNameHint] is provided, returns it directly. Otherwise,
/// captures package lists before/after to detect the newly installed package.
Future<String?> installAndroidInstallablePathAndResolvePackageName(
  String deviceId,
  String installablePath, {
  String? packageNameHint,
}) async {
  final beforePackages = packageNameHint == null
      ? await _listInstalledAndroidPackages(deviceId)
      : null;
  await installAndroidInstallablePath(deviceId, installablePath);
  return packageNameHint ??
      (beforePackages != null
          ? await _resolveInstalledAndroidPackageName(deviceId, beforePackages)
          : null);
}

/// Install an app from a local APK/AAB file.
///
/// Handles both APK (direct install) and AAB (bundletool build + install).
/// Returns metadata about the installed app including package name and
/// inferred display name.
Future<
  ({
    String? archivePath,
    String installablePath,
    String? packageName,
    String? appName,
    String? launchTarget,
  })
>
installAndroidApp(String deviceId, String appPath) async {
  await waitForAndroidBoot(deviceId);

  final prepared = await prepareAndroidInstallArtifact(appPath);
  try {
    final packageName =
        await installAndroidInstallablePathAndResolvePackageName(
          deviceId,
          prepared.installablePath,
          packageNameHint: prepared.packageName,
        );
    final appName = packageName != null
        ? inferAndroidAppName(packageName)
        : null;

    return (
      archivePath: prepared.archivePath,
      installablePath: prepared.installablePath,
      packageName: packageName,
      appName: appName,
      launchTarget: packageName,
    );
  } finally {
    await prepared.cleanup();
  }
}

/// Reinstall an app (uninstall + install).
///
/// Uninstalls by app identifier, then installs from the given path.
/// Preserves the original package name across the reinstall cycle.
Future<({String package})> reinstallAndroidApp(
  String deviceId,
  String app,
  String appPath,
) async {
  await waitForAndroidBoot(deviceId);

  final (:package) = await _uninstallAndroidApp(deviceId, app);
  final prepared = await prepareAndroidInstallArtifact(
    appPath,
    resolveIdentity: false,
  );
  try {
    await installAndroidInstallablePath(deviceId, prepared.installablePath);
    return (package: package);
  } finally {
    await prepared.cleanup();
  }
}

/// Install an APK or AAB file on the device.
///
/// Detects file type (.apk vs .aab) and delegates to appropriate handler.
Future<void> _installAndroidAppFiles(String deviceId, String appPath) async {
  if (_isAndroidAppBundlePath(appPath)) {
    await _installAndroidAppBundle(deviceId, appPath);
    return;
  }
  await runCmd('adb', adbArgs(deviceId, ['install', '-r', appPath]));
}

/// Install an AAB using bundletool.
///
/// Resolves bundletool binary/JAR, builds APKS archive, and installs.
/// Cleans up temporary directory on completion.
Future<void> _installAndroidAppBundle(String deviceId, String appPath) async {
  // TODO(port): Full bundletool integration. For now, stubbed.
  throw UnimplementedError(
    'AAB installation via bundletool not yet implemented',
  );
}

/// Check if a file path is an Android App Bundle (.aab).
bool _isAndroidAppBundlePath(String appPath) {
  return p.extension(appPath).toLowerCase() == '.aab';
}
