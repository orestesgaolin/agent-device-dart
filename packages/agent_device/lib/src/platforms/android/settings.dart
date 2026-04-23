// Port of agent-device/src/platforms/android/settings.ts

import 'dart:async';

import '../../platforms/appearance.dart';
import '../../platforms/permission_utils.dart';
import '../../utils/errors.dart';
import '../../utils/exec.dart';
import 'adb.dart';

const List<String> _androidAnimationScaleSettings = [
  'window_animation_scale',
  'transition_animation_scale',
  'animator_duration_scale',
];

/// Set an Android device setting.
Future<Map<String, Object?>?> setAndroidSetting(
  String serial,
  String setting,
  String state, {
  String? appPackage,
  String? permissionTarget,
  String? permissionMode,
}) async {
  final normalized = setting.toLowerCase();
  switch (normalized) {
    case 'wifi':
      await _setWifiSetting(serial, state);
      return null;
    case 'airplane':
      await _setAirplaneSetting(serial, state);
      return null;
    case 'location':
      await _setLocationSetting(serial, state);
      return null;
    case 'animations':
      return await _setAnimationsSetting(serial, state);
    case 'appearance':
      await _setAppearanceSetting(serial, state);
      return null;
    case 'fingerprint':
      await _setFingerprintSetting(serial, state);
      return null;
    case 'permission':
      await _setPermissionSetting(
        serial,
        state,
        appPackage,
        permissionTarget,
        permissionMode,
      );
      return null;
    default:
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Unsupported setting: $setting',
      );
  }
}

// ===== Setting implementations =====

Future<void> _setWifiSetting(String serial, String state) async {
  final enabled = _parseSettingState(state);
  await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'svc', 'wifi', enabled ? 'enable' : 'disable']),
  );
}

Future<void> _setAirplaneSetting(String serial, String state) async {
  final enabled = _parseSettingState(state);
  final flag = enabled ? '1' : '0';
  final bool_ = enabled ? 'true' : 'false';
  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'settings',
      'put',
      'global',
      'airplane_mode_on',
      flag,
    ]),
  );
  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'am',
      'broadcast',
      '-a',
      'android.intent.action.AIRPLANE_MODE',
      '--ez',
      'state',
      bool_,
    ]),
  );
}

Future<void> _setLocationSetting(String serial, String state) async {
  final enabled = _parseSettingState(state);
  final mode = enabled ? '3' : '0';
  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'settings',
      'put',
      'secure',
      'location_mode',
      mode,
    ]),
  );
}

Future<Map<String, Object?>> _setAnimationsSetting(
  String serial,
  String state,
) async {
  final enabled = _parseSettingState(state);
  final scale = enabled ? '1' : '0';
  for (final key in _androidAnimationScaleSettings) {
    await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'settings', 'put', 'global', key, scale]),
    );
  }
  return {
    'scale': scale,
    'keys': List<String>.from(_androidAnimationScaleSettings),
  };
}

Future<void> _setAppearanceSetting(String serial, String state) async {
  final target = await _resolveAndroidAppearanceTarget(serial, state);
  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'cmd',
      'uimode',
      'night',
      target == 'dark' ? 'yes' : 'no',
    ]),
  );
}

Future<void> _setFingerprintSetting(String serial, String state) async {
  final action = _parseAndroidFingerprintAction(state);
  await _runAndroidFingerprintCommand(serial, action);
}

Future<void> _setPermissionSetting(
  String serial,
  String state,
  String? appPackage,
  String? permissionTarget,
  String? permissionMode,
) async {
  if (appPackage == null) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'permission setting requires an active app in session',
    );
  }
  final action = PermissionAction.fromString(state);
  final target = _parseAndroidPermissionTarget(
    permissionTarget,
    permissionMode,
  );
  if (target is _NotificationsPermissionTarget) {
    await _setAndroidNotificationPermission(serial, appPackage, action, target);
    return;
  }
  final pmTarget = target as _PmPermissionTarget;
  final pmAction = action == PermissionAction.grant ? 'grant' : 'revoke';
  if (pmTarget.type == 'photos') {
    await _setAndroidPhotoPermission(serial, appPackage, pmAction);
    return;
  }
  await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'pm', pmAction, appPackage, pmTarget.value]),
  );
}

// ===== Private helpers =====

String _parseAndroidFingerprintAction(String state) {
  final normalized = state.trim().toLowerCase();
  if (normalized == 'match') return 'match';
  if (normalized == 'nonmatch') return 'nonmatch';
  throw AppError(
    AppErrorCodes.invalidArgs,
    'Invalid fingerprint state: $state. Use match|nonmatch.',
  );
}

Future<void> _runAndroidFingerprintCommand(String serial, String action) async {
  final attempts = _androidFingerprintCommandAttempts(serial, action);
  final failures =
      <({List<String> args, String stdout, String stderr, int exitCode})>[];

  for (final args in attempts) {
    final result = await runCmd(
      'adb',
      adbArgs(serial, args),
      const ExecOptions(allowFailure: true),
    );
    if (result.exitCode == 0) return;
    failures.add((
      args: args,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
    ));
  }

  final attemptsPayload = failures
      .map(
        (f) => {
          'args': f.args.join(' '),
          'exitCode': f.exitCode,
          'stderr': f.stderr.substring(0, (f.stderr.length).clamp(0, 400)),
        },
      )
      .toList();
  final capabilityMissing =
      failures.isNotEmpty &&
      failures.every(
        (f) => _isAndroidFingerprintCapabilityMissing(f.stdout, f.stderr),
      );
  if (capabilityMissing) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'Android fingerprint simulation is not supported on this target/runtime.',
      details: {
        'action': action,
        'hint':
            'Use an Android emulator with biometric support, or a device/runtime that exposes cmd fingerprint.',
        'attempts': attemptsPayload,
      },
    );
  }
  throw AppError(
    AppErrorCodes.commandFailed,
    'Failed to simulate Android fingerprint.',
    details: {'action': action, 'attempts': attemptsPayload},
  );
}

List<List<String>> _androidFingerprintCommandAttempts(
  String serial,
  String action,
) {
  final fingerprintId = action == 'match' ? '1' : '9999';
  return [
    ['shell', 'cmd', 'fingerprint', 'touch', fingerprintId],
    ['shell', 'cmd', 'fingerprint', 'finger', fingerprintId],
  ];
}

bool _isAndroidFingerprintCapabilityMissing(String stdout, String stderr) {
  final text = '$stdout\n$stderr'.toLowerCase();
  return text.contains('unknown command') ||
      text.contains("can't find service: fingerprint") ||
      text.contains('service fingerprint was not found') ||
      text.contains('fingerprint cmd unavailable') ||
      text.contains('emu command is not supported') ||
      text.contains('emulator console is not running') ||
      (text.contains('fingerprint') && text.contains('not found'));
}

bool _parseSettingState(String state) {
  final normalized = state.toLowerCase();
  if (normalized == 'on' || normalized == 'true' || normalized == '1') {
    return true;
  }
  if (normalized == 'off' || normalized == 'false' || normalized == '0') {
    return false;
  }
  throw AppError(AppErrorCodes.invalidArgs, 'Invalid setting state: $state');
}

Future<String> _resolveAndroidAppearanceTarget(
  String serial,
  String state,
) async {
  final action = AppearanceAction.fromString(state);
  if (action != AppearanceAction.toggle) return action.value;

  final currentResult = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'cmd', 'uimode', 'night']),
    const ExecOptions(allowFailure: true),
  );
  if (currentResult.exitCode != 0) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to read current Android appearance',
      details: {
        'stdout': currentResult.stdout,
        'stderr': currentResult.stderr,
        'exitCode': currentResult.exitCode,
      },
    );
  }
  final current = _parseAndroidAppearance(
    currentResult.stdout,
    currentResult.stderr,
  );
  if (current == null) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Unable to determine current Android appearance for toggle',
      details: {'stdout': currentResult.stdout, 'stderr': currentResult.stderr},
    );
  }
  if (current == 'auto') return 'dark';
  return current == 'dark' ? 'light' : 'dark';
}

String? _parseAndroidAppearance(String stdout, String stderr) {
  final match = RegExp(
    r'night mode:\s*(yes|no|auto)\b',
    caseSensitive: false,
  ).firstMatch('$stdout\n$stderr');
  if (match == null) return null;
  final value = match.group(1)!.toLowerCase();
  if (value == 'yes') return 'dark';
  if (value == 'no') return 'light';
  if (value == 'auto') return 'auto';
  return null;
}

class _PmPermissionTarget {
  final String kind = 'pm';
  final String value;
  final String type;

  _PmPermissionTarget({required this.value, required this.type});
}

class _NotificationsPermissionTarget {
  final String kind = 'notifications';
  final String appOps;
  final String permission;

  _NotificationsPermissionTarget({
    required this.appOps,
    required this.permission,
  });
}

Object _parseAndroidPermissionTarget(
  String? permissionTarget,
  String? permissionMode,
) {
  final normalized = PermissionTarget.fromString(permissionTarget);
  if ((permissionMode?.trim() ?? '').isNotEmpty) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Permission mode is only supported for photos. Received: $permissionMode.',
    );
  }
  if (normalized == PermissionTarget.camera) {
    return _PmPermissionTarget(
      value: 'android.permission.CAMERA',
      type: 'camera',
    );
  }
  if (normalized == PermissionTarget.microphone) {
    return _PmPermissionTarget(
      value: 'android.permission.RECORD_AUDIO',
      type: 'microphone',
    );
  }
  if (normalized == PermissionTarget.photos) {
    return _PmPermissionTarget(
      value: 'android.permission.READ_MEDIA_IMAGES',
      type: 'photos',
    );
  }
  if (normalized == PermissionTarget.contacts) {
    return _PmPermissionTarget(
      value: 'android.permission.READ_CONTACTS',
      type: 'contacts',
    );
  }
  if (normalized == PermissionTarget.notifications) {
    return _NotificationsPermissionTarget(
      appOps: 'POST_NOTIFICATION',
      permission: 'android.permission.POST_NOTIFICATIONS',
    );
  }
  // Should not reach here since fromString throws on invalid targets
  throw AppError(
    AppErrorCodes.invalidArgs,
    'Unsupported permission target on Android: $permissionTarget. Use camera|microphone|photos|contacts|notifications.',
  );
}

Future<void> _setAndroidPhotoPermission(
  String serial,
  String appPackage,
  String pmAction,
) async {
  final sdkInt = await _getAndroidSdkInt(serial);
  final candidates = (sdkInt != null && sdkInt >= 33)
      ? [
          'android.permission.READ_MEDIA_IMAGES',
          'android.permission.READ_EXTERNAL_STORAGE',
        ]
      : [
          'android.permission.READ_EXTERNAL_STORAGE',
          'android.permission.READ_MEDIA_IMAGES',
        ];

  final failures = <({String permission, String stderr, int exitCode})>[];
  for (final permission in candidates) {
    final result = await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'pm', pmAction, appPackage, permission]),
      const ExecOptions(allowFailure: true),
    );
    if (result.exitCode == 0) return;
    failures.add((
      permission: permission,
      stderr: result.stderr,
      exitCode: result.exitCode,
    ));
  }

  throw AppError(
    AppErrorCodes.commandFailed,
    'Failed to $pmAction Android photos permission',
    details: {
      'appPackage': appPackage,
      'sdkInt': sdkInt,
      'attempts': failures
          .map(
            (f) => {
              'permission': f.permission,
              'stderr': f.stderr,
              'exitCode': f.exitCode,
            },
          )
          .toList(),
    },
  );
}

Future<void> _setAndroidNotificationPermission(
  String serial,
  String appPackage,
  PermissionAction action,
  _NotificationsPermissionTarget target,
) async {
  final appOpsMode = action == PermissionAction.grant
      ? 'allow'
      : action == PermissionAction.deny
      ? 'deny'
      : 'default';
  if (action == PermissionAction.grant) {
    await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'pm', 'grant', appPackage, target.permission]),
      const ExecOptions(allowFailure: true),
    );
  } else {
    await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'pm', 'revoke', appPackage, target.permission]),
      const ExecOptions(allowFailure: true),
    );
    if (action == PermissionAction.reset) {
      await runCmd(
        'adb',
        adbArgs(serial, [
          'shell',
          'pm',
          'clear-permission-flags',
          appPackage,
          target.permission,
          'user-set',
        ]),
        const ExecOptions(allowFailure: true),
      );
      await runCmd(
        'adb',
        adbArgs(serial, [
          'shell',
          'pm',
          'clear-permission-flags',
          appPackage,
          target.permission,
          'user-fixed',
        ]),
        const ExecOptions(allowFailure: true),
      );
    }
  }
  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'appops',
      'set',
      appPackage,
      target.appOps,
      appOpsMode,
    ]),
  );
}

Future<int?> _getAndroidSdkInt(String serial) async {
  final result = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'getprop', 'ro.build.version.sdk']),
    const ExecOptions(allowFailure: true),
  );
  if (result.exitCode != 0) return null;
  final value = int.tryParse(result.stdout.trim());
  if (value == null || value <= 0) return null;
  return value;
}
