/// Port of agent-device/src/platforms/android/adb.ts.
///
/// Thin wrapper for adb binary path resolution and device-targeting argument
/// construction. Respects ANDROID_ADB environment override.
library;

import '../../../src/utils/errors.dart';
import '../../../src/utils/exec.dart';
import 'sdk.dart';

/// Build adb arguments for targeting a specific device serial.
List<String> adbArgs(String serial, List<String> args) {
  return ['-s', serial, ...args];
}

/// Ensure adb is available in PATH or via SDK configuration.
///
/// Configures ANDROID_SDK_ROOT and PATH from env if needed, then checks
/// that adb is available via whichCmd. Throws [AppError] with code
/// 'TOOL_MISSING' if adb cannot be found.
Future<void> ensureAdb() async {
  await ensureAndroidSdkPathConfigured();
  final adbAvailable = await whichCmd('adb');
  if (!adbAvailable) {
    throw AppError(AppErrorCodes.toolMissing, 'adb not found in PATH');
  }
}

/// Check if a shell command error indicates unsupported clipboard shell.
///
/// Android devices prior to API 29 do not support clipboard shell commands.
/// This function checks stdout/stderr for known error markers that indicate
/// the device lacks shell support for clipboard operations.
bool isClipboardShellUnsupported(String stdout, String stderr) {
  final haystack = '$stdout\n$stderr'.toLowerCase();
  return haystack.contains('no shell command implementation') ||
      haystack.contains('unknown command');
}
