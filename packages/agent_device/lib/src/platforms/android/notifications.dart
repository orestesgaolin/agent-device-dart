// Port of agent-device/src/platforms/android/notifications.ts

import '../../utils/errors.dart';
import '../../utils/exec.dart';
import 'adb.dart';

/// Payload for pushing an Android broadcast notification.
class AndroidBroadcastPayload {
  final String? action;
  final String? receiver;
  final Map<String, Object?>? extras;

  const AndroidBroadcastPayload({this.action, this.receiver, this.extras});
}

/// Result of pushing an Android notification.
class AndroidNotificationResult {
  final String action;
  final int extrasCount;

  const AndroidNotificationResult({
    required this.action,
    required this.extrasCount,
  });
}

/// Pushes an Android broadcast notification to the given device.
Future<AndroidNotificationResult> pushAndroidNotification(
  String serial,
  String packageName,
  AndroidBroadcastPayload payload,
) async {
  final action = (payload.action != null && payload.action!.trim().isNotEmpty)
      ? payload.action!.trim()
      : '$packageName.TEST_PUSH';

  final args = ['shell', 'am', 'broadcast', '-a', action, '-p', packageName];

  final receiver = (payload.receiver != null) ? payload.receiver!.trim() : '';
  if (receiver.isNotEmpty) {
    args.addAll(['-n', receiver]);
  }

  final extras = payload.extras ?? <String, Object?>{};
  int extrasCount = 0;

  for (final MapEntry(key: key, value: value) in extras.entries) {
    if (key.isEmpty) continue;
    _appendBroadcastExtra(args, key, value);
    extrasCount += 1;
  }

  await runCmd('adb', adbArgs(serial, args));
  return AndroidNotificationResult(action: action, extrasCount: extrasCount);
}

void _appendBroadcastExtra(List<String> args, String key, Object? value) {
  if (value is String) {
    args.addAll(['--es', key, value]);
    return;
  }
  if (value is bool) {
    args.addAll(['--ez', key, value ? 'true' : 'false']);
    return;
  }
  if (value is num && value.isFinite) {
    if (value is int) {
      args.addAll(['--ei', key, value.toString()]);
      return;
    }
    args.addAll(['--ef', key, value.toString()]);
    return;
  }
  throw AppError(
    AppErrorCodes.invalidArgs,
    'Unsupported Android broadcast extra type for "$key". '
    'Use string, boolean, or number.',
  );
}
