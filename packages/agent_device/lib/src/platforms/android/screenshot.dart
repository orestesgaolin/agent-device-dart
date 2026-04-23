// Port of agent-device/src/platforms/android/screenshot.ts

import 'dart:io';
import 'dart:typed_data';

import '../../utils/errors.dart';
import '../../utils/exec.dart';
import '../../utils/timeouts.dart';
import 'adb.dart';

/// PNG file signature: 0x89 P N G \r \n 0x1A \n
final _pngSignature = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
]);

/// Delay to allow transient UI elements (scrollbars, etc.) to fade.
const _androidScreenshotSettleDelayMs = 1000;

/// Capture a screenshot from the Android device.
///
/// Enables demo mode for consistent status bar appearance, waits for
/// transient UI elements to settle, captures via `adb exec-out screencap -p`,
/// and then disables demo mode.
Future<void> screenshotAndroid(String serial, String outPath) async {
  await _enableAndroidDemoMode(serial);
  try {
    await sleep(const Duration(milliseconds: _androidScreenshotSettleDelayMs));
    await _captureAndroidScreenshot(serial, outPath);
  } finally {
    await _disableAndroidDemoMode(serial).catchError((_) {});
  }
}

/// Enable demo mode with deterministic time in status bar.
///
/// This ensures consistent screenshots across test runs by hiding
/// live status bar elements and showing a fixed time.
Future<void> _enableAndroidDemoMode(String serial) async {
  Future<void> shell(String cmd) => runCmd(
    'adb',
    adbArgs(serial, ['shell', cmd]),
    const ExecOptions(allowFailure: true),
  ).then((_) {});

  await shell('settings put global sysui_demo_allowed 1');

  Future<void> broadcast(String extra) =>
      shell('am broadcast -a com.android.systemui.demo -e command $extra');

  await broadcast('clock -e hhmm 0941');
  await broadcast('notifications -e visible false');
}

/// Disable demo mode and restore the live status bar.
Future<void> _disableAndroidDemoMode(String serial) async {
  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'am broadcast -a com.android.systemui.demo -e command exit',
    ]),
    const ExecOptions(allowFailure: true),
  );
}

/// Capture screenshot via adb, extract PNG data, and write to file.
///
/// On multi-display devices (e.g. Galaxy Z Fold), adb may output warnings
/// before the PNG. This function locates the PNG signature and extracts
/// only the valid PNG data, discarding leading/trailing garbage.
Future<void> _captureAndroidScreenshot(String serial, String outPath) async {
  final result = await runCmd(
    'adb',
    adbArgs(serial, ['exec-out', 'screencap', '-p']),
    const ExecOptions(binaryStdout: true),
  );

  final stdoutBuffer = result.stdoutBuffer;
  if (stdoutBuffer == null || stdoutBuffer.isEmpty) {
    throw AppError(AppErrorCodes.commandFailed, 'Failed to capture screenshot');
  }

  final pngOffset = _findIndex(stdoutBuffer, _pngSignature);
  if (pngOffset < 0) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Screenshot data does not contain a valid PNG header',
    );
  }

  final pngEndOffset = _findPngEndOffset(stdoutBuffer, pngOffset);
  if (pngEndOffset == null) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Screenshot data does not contain a complete PNG payload',
    );
  }

  final pngData = Uint8List.fromList(
    stdoutBuffer.sublist(pngOffset, pngEndOffset),
  );
  await File(outPath).writeAsBytes(pngData);
}

/// Find the PNG end offset by scanning chunk headers.
///
/// PNG files consist of an 8-byte signature followed by 4-byte length,
/// 4-byte type, variable-length data, and 4-byte CRC. The IEND chunk
/// marks the end of the file.
int? _findPngEndOffset(List<int> buffer, int pngStartOffset) {
  var offset = pngStartOffset + _pngSignature.length;

  while (offset + 8 <= buffer.length) {
    final chunkLength = _readUint32BE(buffer, offset);
    final chunkTypeOffset = offset + 4;
    final chunkType = String.fromCharCodes(
      buffer.sublist(chunkTypeOffset, chunkTypeOffset + 4),
    );
    final chunkEnd =
        offset + 12 + chunkLength; // len(4) + type(4) + data + crc(4)

    if (chunkEnd > buffer.length) return null;
    if (chunkType == 'IEND') return chunkEnd;

    offset = chunkEnd;
  }

  return null;
}

/// Read a big-endian 32-bit unsigned integer from a byte list.
int _readUint32BE(List<int> buffer, int offset) {
  return ((buffer[offset] & 0xFF) << 24) |
      ((buffer[offset + 1] & 0xFF) << 16) |
      ((buffer[offset + 2] & 0xFF) << 8) |
      (buffer[offset + 3] & 0xFF);
}

/// Find the first occurrence of a pattern in a byte buffer.
///
/// Returns the index of the first byte of the pattern, or -1 if not found.
int _findIndex(List<int> buffer, List<int> pattern) {
  if (pattern.isEmpty || pattern.length > buffer.length) return -1;

  outer:
  for (var i = 0; i <= buffer.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (buffer[i + j] != pattern[j]) {
        continue outer;
      }
    }
    return i;
  }

  return -1;
}
