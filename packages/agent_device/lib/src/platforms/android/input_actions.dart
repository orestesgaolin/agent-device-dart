// Port of agent-device/src/platforms/android/input-actions.ts

import 'dart:async';

import '../../core/device_rotation.dart';
import '../../core/scroll_gesture.dart';
import '../../utils/errors.dart';
import '../../utils/exec.dart';
import '../../utils/timeouts.dart';
import 'adb.dart';
import 'snapshot.dart';
import 'ui_hierarchy.dart';

/// Tap at the specified coordinates.
Future<void> pressAndroid(String serial, int x, int y) async {
  await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'input', 'tap', x.toString(), y.toString()]),
  );
}

/// Swipe from (x1, y1) to (x2, y2) over the specified duration.
Future<void> swipeAndroid(
  String serial,
  int x1,
  int y1,
  int x2,
  int y2, [
  int durationMs = 250,
]) async {
  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'input',
      'swipe',
      x1.toString(),
      y1.toString(),
      x2.toString(),
      y2.toString(),
      durationMs.toString(),
    ]),
  );
}

/// Press the back button.
Future<void> backAndroid(String serial) async {
  await runCmd('adb', adbArgs(serial, ['shell', 'input', 'keyevent', '4']));
}

/// Press the home button.
Future<void> homeAndroid(String serial) async {
  await runCmd('adb', adbArgs(serial, ['shell', 'input', 'keyevent', '3']));
}

/// Rotate the device to the specified orientation.
Future<void> rotateAndroid(String serial, DeviceRotation orientation) async {
  final userRotation = _resolveAndroidUserRotation(orientation);
  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'settings',
      'put',
      'system',
      'accelerometer_rotation',
      '0',
    ]),
  );
  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'settings',
      'put',
      'system',
      'user_rotation',
      userRotation,
    ]),
  );
}

/// Press the app switcher button.
Future<void> appSwitcherAndroid(String serial) async {
  await runCmd('adb', adbArgs(serial, ['shell', 'input', 'keyevent', '187']));
}

/// Long press at the specified coordinates.
Future<void> longPressAndroid(
  String serial,
  int x,
  int y, [
  int durationMs = 800,
]) async {
  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'input',
      'swipe',
      x.toString(),
      y.toString(),
      x.toString(),
      y.toString(),
      durationMs.toString(),
    ]),
  );
}

/// Type text with optional per-character delay.
Future<void> typeAndroid(String serial, String text, [int delayMs = 0]) async {
  if (delayMs > 0 && text.runes.length > 1) {
    await _typeAndroidChunked(serial, text, 1, delayMs);
    return;
  }
  await _typeAndroidImmediate(serial, text);
}

/// Focus on the specified coordinates (equivalent to press).
Future<void> focusAndroid(String serial, int x, int y) async {
  await pressAndroid(serial, x, y);
}

/// Fill a text field by focusing, clearing, and typing text.
Future<void> fillAndroid(
  String serial,
  int x,
  int y,
  String text, [
  int delayMs = 0,
]) async {
  final textCodePointLength = text.runes.length;
  final requiresClipboardInjection = _shouldUseClipboardTextInjection(text);
  final attempts =
      <({String strategy, int clearPadding, int minClear, int maxClear})>[
        (strategy: 'input_text', clearPadding: 12, minClear: 8, maxClear: 48),
      ];
  if (!requiresClipboardInjection && delayMs <= 0) {
    attempts.add((
      strategy: 'clipboard_paste',
      clearPadding: 12,
      minClear: 8,
      maxClear: 48,
    ));
  }
  if (!requiresClipboardInjection || delayMs > 0) {
    attempts.add((
      strategy: 'chunked_input',
      clearPadding: 24,
      minClear: 16,
      maxClear: 96,
    ));
  }

  String? lastActual;

  for (final attempt in attempts) {
    await focusAndroid(serial, x, y);
    final clearCount = _clampCount(
      textCodePointLength + attempt.clearPadding,
      attempt.minClear,
      attempt.maxClear,
    );
    await _clearFocusedText(serial, clearCount);
    if (attempt.strategy == 'input_text') {
      await typeAndroid(serial, text, delayMs);
    } else if (attempt.strategy == 'clipboard_paste') {
      final clipboardResult = await _typeAndroidViaClipboard(serial, text);
      if (clipboardResult != 'ok') {
        continue;
      }
    } else {
      await _typeAndroidChunked(serial, text, 1, delayMs > 0 ? delayMs : 15);
    }
    final verification = await _verifyAndroidFilledText(serial, x, y, text);
    lastActual = verification.actual;
    if (verification.ok) return;
  }

  throw AppError(
    AppErrorCodes.commandFailed,
    'Android fill verification failed',
    details: {'expected': text, 'actual': lastActual},
  );
}

/// Scroll in the specified direction with optional amount or pixel override.
Future<Map<String, Object?>> scrollAndroid(
  String serial,
  ScrollDirection direction, {
  double? amount,
  double? pixels,
}) async {
  final size = await getAndroidScreenSize(serial);
  final plan = buildScrollGesturePlan(
    ScrollGestureOptions(
      direction: direction,
      amount: amount,
      pixels: pixels,
      referenceWidth: size['width']!,
      referenceHeight: size['height']!,
    ),
  );

  await runCmd(
    'adb',
    adbArgs(serial, [
      'shell',
      'input',
      'swipe',
      plan.x1.toString(),
      plan.y1.toString(),
      plan.x2.toString(),
      plan.y2.toString(),
      '300',
    ]),
  );

  return {
    'direction': plan.direction.value,
    'x1': plan.x1,
    'y1': plan.y1,
    'x2': plan.x2,
    'y2': plan.y2,
    'pixels': plan.pixels,
    'referenceWidth': plan.referenceWidth,
    'referenceHeight': plan.referenceHeight,
  };
}

/// Get the physical screen size.
Future<Map<String, int>> getAndroidScreenSize(String serial) async {
  final result = await runCmd('adb', adbArgs(serial, ['shell', 'wm', 'size']));
  final match = RegExp(
    r'Physical size:\s*(\d+)x(\d+)',
  ).firstMatch(result.stdout);
  if (match == null) {
    throw AppError(AppErrorCodes.commandFailed, 'Unable to read screen size');
  }
  return {
    'width': int.parse(match.group(1)!),
    'height': int.parse(match.group(2)!),
  };
}

/// Read text content at the specified point from the UI hierarchy.
Future<String?> readAndroidTextAtPoint(String serial, int x, int y) async {
  final xml = await dumpUiHierarchy(serial);
  final nodeRegex = RegExp(r'<node\b[^>]*>');
  ({String text, int area})? focusedEdit;
  ({String text, int area})? editAtPoint;
  ({String text, int area})? anyAtPoint;

  for (final match in nodeRegex.allMatches(xml)) {
    final node = match.group(0)!;
    final attrs = readNodeAttributes(node);
    final rect = parseBounds(attrs.bounds);
    if (rect == null) continue;
    final className = attrs.className ?? '';
    final text = _decodeXmlEntities(attrs.text ?? '');
    final focused = attrs.focused ?? false;
    if (text.isEmpty) continue;
    final area = ((rect.width * rect.height).abs().round()).clamp(1, 1 << 30);
    final containsPoint =
        x >= rect.x &&
        x <= (rect.x + rect.width).toInt() &&
        y >= rect.y &&
        y <= (rect.y + rect.height).toInt();

    if (focused && _isEditTextClass(className)) {
      if (focusedEdit == null || area <= focusedEdit.area) {
        focusedEdit = (text: text, area: area);
      }
      continue;
    }
    if (containsPoint && _isEditTextClass(className)) {
      if (editAtPoint == null || area <= editAtPoint.area) {
        editAtPoint = (text: text, area: area);
      }
      continue;
    }
    if (containsPoint) {
      if (anyAtPoint == null || area <= anyAtPoint.area) {
        anyAtPoint = (text: text, area: area);
      }
    }
  }

  return focusedEdit?.text ?? editAtPoint?.text ?? anyAtPoint?.text;
}

// ===== Private helpers =====

String _resolveAndroidUserRotation(DeviceRotation orientation) {
  return switch (orientation) {
    DeviceRotation.portrait => '0',
    DeviceRotation.landscapeLeft => '1',
    DeviceRotation.portraitUpsideDown => '2',
    DeviceRotation.landscapeRight => '3',
  };
}

Future<void> _typeAndroidImmediate(String serial, String text) async {
  final shouldInjectViaClipboard = _shouldUseClipboardTextInjection(text);
  if (shouldInjectViaClipboard) {
    final clipboardResult = await _typeAndroidViaClipboard(serial, text);
    if (clipboardResult == 'ok') return;
  }
  try {
    final encoded = _encodeAndroidInputText(text);
    await runCmd('adb', adbArgs(serial, ['shell', 'input', 'text', encoded]));
  } catch (error) {
    if (shouldInjectViaClipboard && _isAndroidInputTextUnsupported(error)) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'Non-ASCII text input is not supported on this Android shell. Install an ADB keyboard IME or use ASCII input.',
        details: {'textPreview': text.substring(0, (text.length).clamp(0, 32))},
        cause: error is Exception ? error : null,
      );
    }
    rethrow;
  }
}

Future<void> _typeAndroidChunked(
  String serial,
  String text,
  int chunkSize,
  int delayMs,
) async {
  final size = (chunkSize).clamp(1, double.infinity).toInt();
  final chars = text.split('');
  for (int i = 0; i < chars.length; i += size) {
    final chunk = chars.sublist(i, (i + size).clamp(0, chars.length)).join();
    await _typeAndroidImmediate(serial, chunk);
    if (delayMs > 0 && i + size < chars.length) {
      await sleep(Duration(milliseconds: delayMs));
    }
  }
}

bool _shouldUseClipboardTextInjection(String text) {
  for (final codePoint in text.runes) {
    if (codePoint < 0x20 || codePoint > 0x7e) return true;
  }
  return false;
}

String _encodeAndroidInputText(String text) {
  return text.replaceAll(' ', '%s');
}

Future<({String? actual, bool ok})> _verifyAndroidFilledText(
  String serial,
  int x,
  int y,
  String expected,
) async {
  const verificationDelaysMs = [0, 150, 350];
  String? lastActual;

  for (final delayMs in verificationDelaysMs) {
    if (delayMs > 0) {
      await sleep(Duration(milliseconds: delayMs));
    }
    lastActual = await readAndroidTextAtPoint(serial, x, y);
    if (_isAcceptableAndroidFillMatch(lastActual, expected)) {
      return (actual: lastActual, ok: true);
    }
  }

  return (actual: lastActual, ok: false);
}

bool _isAcceptableAndroidFillMatch(String? actual, String expected) {
  if (actual == expected) {
    return true;
  }
  final normalizedActual = _normalizeFillVerificationText(actual);
  final normalizedExpected = _normalizeFillVerificationText(expected);
  if (normalizedActual.isEmpty || normalizedExpected.isEmpty) {
    return false;
  }
  if (normalizedActual == normalizedExpected) {
    return true;
  }
  if (normalizedActual.contains(normalizedExpected)) {
    return true;
  }
  return normalizedExpected.contains(normalizedActual) &&
      normalizedActual.length >=
          (4).clamp(4, (normalizedExpected.length * 0.8).floor());
}

String _normalizeFillVerificationText(String? value) {
  return (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

Future<String> _typeAndroidViaClipboard(String serial, String text) async {
  final setClipboard = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'cmd', 'clipboard', 'set', 'text', text]),
    const ExecOptions(allowFailure: true),
  );
  if (setClipboard.exitCode != 0) return 'failed';
  if (isClipboardShellUnsupported(setClipboard.stdout, setClipboard.stderr)) {
    return 'unsupported';
  }

  final pasteByName = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'input', 'keyevent', 'KEYCODE_PASTE']),
    const ExecOptions(allowFailure: true),
  );
  if (pasteByName.exitCode == 0) return 'ok';

  final pasteByCode = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'input', 'keyevent', '279']),
    const ExecOptions(allowFailure: true),
  );
  return pasteByCode.exitCode == 0 ? 'ok' : 'failed';
}

bool _isAndroidInputTextUnsupported(Object error) {
  if (error is! AppError) return false;
  if (error.code != AppErrorCodes.commandFailed) return false;
  final rawStderr = error.details?['stderr'];
  final stderr = (rawStderr is String ? rawStderr : '').toLowerCase();
  if (stderr.contains("exception occurred while executing 'text'")) return true;
  if (stderr.contains('nullpointerexception') &&
      stderr.contains('inputshellcommand.sendtext')) {
    return true;
  }
  return false;
}

Future<void> _clearFocusedText(String serial, int count) async {
  final deletes = (count).clamp(0, double.infinity).toInt();
  await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'input', 'keyevent', 'KEYCODE_MOVE_END']),
    const ExecOptions(allowFailure: true),
  );
  const batchSize = 24;
  for (int i = 0; i < deletes; i += batchSize) {
    final size = (batchSize).clamp(0, deletes - i);
    final keyEvents = List<String>.filled(size, 'KEYCODE_DEL');
    await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'input', 'keyevent', ...keyEvents]),
      const ExecOptions(allowFailure: true),
    );
  }
}

bool _isEditTextClass(String className) {
  final lower = className.toLowerCase();
  return lower.contains('edittext') || lower.contains('textfield');
}

String _decodeXmlEntities(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

int _clampCount(int value, int min, int max) {
  return value.clamp(min, max);
}
