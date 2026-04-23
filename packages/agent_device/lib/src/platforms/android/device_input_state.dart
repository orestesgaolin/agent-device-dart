// Port of agent-device/src/platforms/android/device-input-state.ts

import '../../utils/errors.dart';
import '../../utils/exec.dart';
import '../../utils/timeouts.dart';
import 'adb.dart';

const int _androidInputTypeClassMask = 0x0000000f;
const int _androidInputTypeClassText = 0x00000001;
const int _androidInputTypeClassNumber = 0x00000002;
const int _androidInputTypeClassPhone = 0x00000003;
const int _androidInputTypeClassDatetime = 0x00000004;
const int _androidInputTypeVariationMask = 0x00000ff0;
const int _androidTextVariationEmailAddress = 0x00000020;
const int _androidTextVariationWebEmailAddress = 0x000000d0;
const int _androidTextVariationPassword = 0x00000080;
const int _androidTextVariationWebPassword = 0x000000e0;
const int _androidTextVariationVisiblePassword = 0x00000090;
const int _androidKeyboardDismissMaxAttempts = 2;
const int _androidKeyboardDismissRetryDelayMs = 120;
const String _androidKeycodeEscape = '111';

enum AndroidKeyboardType {
  text('text'),
  number('number'),
  email('email'),
  phone('phone'),
  password('password'),
  datetime('datetime'),
  unknown('unknown');

  final String value;

  const AndroidKeyboardType(this.value);

  @override
  String toString() => value;
}

/// State of the Android keyboard.
class AndroidKeyboardState {
  final bool visible;
  final String? inputType;
  final AndroidKeyboardType? type;

  const AndroidKeyboardState({
    required this.visible,
    this.inputType,
    this.type,
  });
}

/// Result of dismissing the Android keyboard.
class AndroidKeyboardDismissResult {
  final int attempts;
  final bool wasVisible;
  final bool dismissed;
  final bool visible;
  final String? inputType;
  final AndroidKeyboardType? type;

  const AndroidKeyboardDismissResult({
    required this.attempts,
    required this.wasVisible,
    required this.dismissed,
    required this.visible,
    this.inputType,
    this.type,
  });
}

/// Gets the current state of the Android keyboard.
Future<AndroidKeyboardState> getAndroidKeyboardState(String serial) async {
  final result = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'dumpsys', 'input_method']),
    const ExecOptions(allowFailure: true),
  );
  if (result.exitCode != 0) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to query Android keyboard state',
      details: {
        'stdout': result.stdout,
        'stderr': result.stderr,
        'exitCode': result.exitCode,
      },
    );
  }
  return _parseAndroidKeyboardState(result.stdout);
}

/// Dismisses the Android keyboard.
Future<AndroidKeyboardDismissResult> dismissAndroidKeyboard(
  String serial,
) async {
  final initialState = await getAndroidKeyboardState(serial);
  var state = initialState;
  var attempts = 0;

  while (state.visible && attempts < _androidKeyboardDismissMaxAttempts) {
    await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'input', 'keyevent', _androidKeycodeEscape]),
    );
    attempts += 1;
    await sleep(
      const Duration(milliseconds: _androidKeyboardDismissRetryDelayMs),
    );
    state = await getAndroidKeyboardState(serial);
  }

  if (initialState.visible && state.visible) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'Android keyboard dismiss is unavailable for the current IME without back navigation.',
      details: {
        'attempts': attempts,
        'inputType': state.inputType,
        'type': state.type?.value,
      },
    );
  }

  return AndroidKeyboardDismissResult(
    attempts: attempts,
    wasVisible: initialState.visible,
    dismissed: initialState.visible && !state.visible,
    visible: state.visible,
    inputType: state.inputType,
    type: state.type,
  );
}

AndroidKeyboardState _parseAndroidKeyboardState(String stdout) {
  bool visible = _parseAndroidKeyboardVisibility(stdout) ?? false;

  if (visible == false) {
    final imeWindowVisibility = RegExp(
      r'\bmImeWindowVis=0x([0-9a-fA-F]+)\b',
    ).firstMatch(stdout);
    if (imeWindowVisibility != null) {
      final flags = int.tryParse(imeWindowVisibility.group(1) ?? '', radix: 16);
      if (flags != null) {
        visible = (flags & 0x1) != 0;
      }
    }
  }

  final inputTypeMatches = RegExp(
    r'\binputType=0x([0-9a-fA-F]+)\b',
    multiLine: true,
  ).allMatches(stdout).toList();
  final lastInputType = inputTypeMatches.isNotEmpty
      ? inputTypeMatches.last.group(1)
      : null;
  final inputType = lastInputType != null
      ? '0x${lastInputType.toLowerCase()}'
      : null;

  return AndroidKeyboardState(
    visible: visible,
    inputType: inputType,
    type: inputType != null ? _classifyAndroidKeyboardType(inputType) : null,
  );
}

bool? _parseAndroidKeyboardVisibility(String stdout) {
  final latestByKey = <String, bool>{};
  final pattern = RegExp(
    r'\b(mInputShown|mIsInputViewShown|isInputViewShown)=([a-zA-Z]+)\b',
  );

  for (final match in pattern.allMatches(stdout)) {
    final key = match.group(1);
    final value = match.group(2)?.toLowerCase();
    if (key != null && (value == 'true' || value == 'false')) {
      latestByKey[key] = value == 'true';
    }
  }

  if (latestByKey.isEmpty) return null;

  for (final visible in latestByKey.values) {
    if (visible) return true;
  }
  return false;
}

AndroidKeyboardType _classifyAndroidKeyboardType(String inputType) {
  final parsed = int.tryParse(
    inputType.replaceFirst(RegExp('^0x', caseSensitive: false), ''),
    radix: 16,
  );
  if (parsed == null) return AndroidKeyboardType.unknown;

  final inputClass = parsed & _androidInputTypeClassMask;
  if (inputClass == _androidInputTypeClassNumber) {
    return AndroidKeyboardType.number;
  }
  if (inputClass == _androidInputTypeClassPhone) {
    return AndroidKeyboardType.phone;
  }
  if (inputClass == _androidInputTypeClassDatetime) {
    return AndroidKeyboardType.datetime;
  }
  if (inputClass != _androidInputTypeClassText) {
    return AndroidKeyboardType.unknown;
  }

  final variation = parsed & _androidInputTypeVariationMask;
  if (variation == _androidTextVariationEmailAddress ||
      variation == _androidTextVariationWebEmailAddress) {
    return AndroidKeyboardType.email;
  }
  if (variation == _androidTextVariationPassword ||
      variation == _androidTextVariationWebPassword ||
      variation == _androidTextVariationVisiblePassword) {
    return AndroidKeyboardType.password;
  }
  return AndroidKeyboardType.text;
}

/// Reads text from the Android clipboard.
Future<String> readAndroidClipboardText(String serial) async {
  final stdout = await _runAndroidClipboardShellCommand(serial, [
    'shell',
    'cmd',
    'clipboard',
    'get',
    'text',
  ], 'read');
  return _normalizeAndroidClipboardText(stdout);
}

/// Writes text to the Android clipboard.
Future<void> writeAndroidClipboardText(String serial, String text) async {
  await _runAndroidClipboardShellCommand(serial, [
    'shell',
    'cmd',
    'clipboard',
    'set',
    'text',
    text,
  ], 'write');
}

Future<String> _runAndroidClipboardShellCommand(
  String serial,
  List<String> args,
  String operation,
) async {
  final result = await runCmd(
    'adb',
    adbArgs(serial, args),
    const ExecOptions(allowFailure: true),
  );

  if (isClipboardShellUnsupported(result.stdout, result.stderr)) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'Android shell clipboard $operation is not supported on this device.',
    );
  }

  if (result.exitCode != 0) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to $operation Android clipboard text',
      details: {
        'stdout': result.stdout,
        'stderr': result.stderr,
        'exitCode': result.exitCode,
      },
    );
  }

  return result.stdout;
}

String _normalizeAndroidClipboardText(String stdout) {
  final normalized = stdout
      .replaceAll('\r\n', '\n')
      .replaceFirst(RegExp(r'\n$'), '');
  final prefixed = RegExp(
    r'^clipboard text:\s*(.*)$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (prefixed != null) return prefixed.group(1) ?? '';
  if (normalized.trim().toLowerCase() == 'null') return '';
  return normalized;
}
