/// Port of `agent-device/src/utils/errors.ts`.
///
/// [AppError] is the canonical exception type for agent_device. Public-facing
/// failures are produced through [normalizeError] / [normalizeAgentDeviceError],
/// which attach hints, diagnostic ids, and redacted detail payloads.
library;

import 'dart:io' show Platform;

import 'redaction.dart';

/// Global verbose flag. Set by the CLI when `--verbose` / `--debug` is passed.
/// Platform modules check this to emit diagnostic logs.
bool agentDeviceVerbose = Platform.environment['AGENT_DEVICE_VERBOSE'] == '1';

/// Known error codes. Additional strings flow through verbatim so that
/// daemon-originated codes round-trip without a union update. Consumers
/// switching on `code` should always include a default branch.
class AppErrorCodes {
  static const String invalidArgs = 'INVALID_ARGS';
  static const String deviceNotFound = 'DEVICE_NOT_FOUND';
  static const String deviceInUse = 'DEVICE_IN_USE';
  static const String toolMissing = 'TOOL_MISSING';
  static const String appNotInstalled = 'APP_NOT_INSTALLED';
  static const String unsupportedPlatform = 'UNSUPPORTED_PLATFORM';
  static const String unsupportedOperation = 'UNSUPPORTED_OPERATION';
  static const String notImplemented = 'NOT_IMPLEMENTED';
  static const String commandFailed = 'COMMAND_FAILED';
  static const String sessionNotFound = 'SESSION_NOT_FOUND';
  static const String unauthorized = 'UNAUTHORIZED';
  static const String ambiguousMatch = 'AMBIGUOUS_MATCH';
  static const String unknown = 'UNKNOWN';

  const AppErrorCodes._();
}

/// Accepts any string so daemon-provided codes pass through. Use
/// [AppErrorCodes] constants for the known set.
String toAppErrorCode(
  String? code, {
  String fallback = AppErrorCodes.commandFailed,
}) {
  if (code != null && code.isNotEmpty) return code;
  return fallback;
}

/// Public, redacted error shape returned to SDK consumers and CLI output.
class NormalizedError {
  final String code;
  final String message;
  final String? hint;
  final String? diagnosticId;
  final String? logPath;
  final Map<String, Object?>? details;

  const NormalizedError({
    required this.code,
    required this.message,
    this.hint,
    this.diagnosticId,
    this.logPath,
    this.details,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (hint != null) 'hint': hint,
    if (diagnosticId != null) 'diagnosticId': diagnosticId,
    if (logPath != null) 'logPath': logPath,
    if (details != null) 'details': details,
  };
}

/// Canonical exception type. Carries a stable [code], a human [message], an
/// optional [details] map (may contain `hint` / `diagnosticId` / `logPath`),
/// and an optional underlying [cause].
class AppError implements Exception {
  final String code;
  final String message;
  final Map<String, Object?>? details;
  final Object? cause;

  AppError(this.code, this.message, {this.details, this.cause});

  @override
  String toString() => 'AppError($code): $message';
}

/// Coerces any thrown value into an [AppError]. Existing [AppError]s pass
/// through; other [Exception]/[Error] instances become `UNKNOWN` with their
/// original `toString()` as the message.
AppError asAppError(Object? err) {
  if (err is AppError) return err;
  if (err is Error) {
    return AppError(AppErrorCodes.unknown, err.toString(), cause: err);
  }
  if (err is Exception) {
    return AppError(AppErrorCodes.unknown, err.toString(), cause: err);
  }
  return AppError(
    AppErrorCodes.unknown,
    'Unknown error',
    details: {'err': err},
  );
}

/// True if [err] is an [AppError].
bool isAgentDeviceError(Object? err) => err is AppError;

/// Back-compat alias for [normalizeError] exposed under the longer public name.
NormalizedError normalizeAgentDeviceError(
  Object? err, {
  String? diagnosticId,
  String? logPath,
}) => normalizeError(err, diagnosticId: diagnosticId, logPath: logPath);

/// Converts [err] into a [NormalizedError] with redacted details, a hint
/// (explicit → detail-provided → code-default), and propagated diagnostic
/// metadata. Matches the Node implementation's behavior including the
/// `COMMAND_FAILED` stderr-excerpt enrichment.
NormalizedError normalizeError(
  Object? err, {
  String? diagnosticId,
  String? logPath,
}) {
  final appErr = asAppError(err);
  final redacted = appErr.details != null
      ? redactDiagnosticData(appErr.details) as Map<String, Object?>?
      : null;

  final detailHint = redacted?['hint'];
  final detailDiagnosticId = redacted?['diagnosticId'];
  final detailLogPath = redacted?['logPath'];

  final resolvedDiagnosticId =
      (detailDiagnosticId is String ? detailDiagnosticId : null) ??
      diagnosticId;
  final resolvedLogPath =
      (detailLogPath is String ? detailLogPath : null) ?? logPath;
  final resolvedHint =
      (detailHint is String ? detailHint : null) ??
      defaultHintForCode(appErr.code);

  final cleanDetails = _stripDiagnosticMeta(redacted);
  final message = _maybeEnrichCommandFailedMessage(
    appErr.code,
    appErr.message,
    redacted,
  );

  return NormalizedError(
    code: appErr.code,
    message: message,
    hint: resolvedHint,
    diagnosticId: resolvedDiagnosticId,
    logPath: resolvedLogPath,
    details: cleanDetails,
  );
}

String _maybeEnrichCommandFailedMessage(
  String code,
  String message,
  Map<String, Object?>? details,
) {
  if (code != AppErrorCodes.commandFailed) return message;
  if (details == null) return message;
  if (details['processExitError'] != true) return message;
  final stderr = details['stderr'];
  if (stderr is! String) return message;
  final excerpt = _firstStderrLine(stderr);
  if (excerpt == null) return message;
  return excerpt;
}

final List<RegExp> _stderrSkipPatterns = <RegExp>[
  RegExp(
    r'^an error was encountered processing the command',
    caseSensitive: false,
  ),
  RegExp(r'^underlying error\b', caseSensitive: false),
  RegExp(
    r'^simulator device failed to complete the requested operation',
    caseSensitive: false,
  ),
];

String? _firstStderrLine(String stderr) {
  for (final rawLine in stderr.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (_stderrSkipPatterns.any((p) => p.hasMatch(line))) continue;
    return line.length > 200 ? '${line.substring(0, 200)}...' : line;
  }
  return null;
}

Map<String, Object?>? _stripDiagnosticMeta(Map<String, Object?>? details) {
  if (details == null) return null;
  final output = <String, Object?>{...details};
  output.remove('hint');
  output.remove('diagnosticId');
  output.remove('logPath');
  return output.isEmpty ? null : output;
}

/// Default hint string for [code], or null when no default applies.
String? defaultHintForCode(String code) {
  switch (code) {
    case AppErrorCodes.invalidArgs:
      return 'Check command arguments and run --help for usage examples.';
    case AppErrorCodes.sessionNotFound:
      return 'Run open first or pass an explicit device selector.';
    case AppErrorCodes.toolMissing:
      return 'Install required platform tooling and ensure it is available in PATH.';
    case AppErrorCodes.deviceNotFound:
      return 'Verify the target device is booted/connected and selectors match.';
    case AppErrorCodes.appNotInstalled:
      return 'Run apps to discover the exact installed package or bundle id, or install the app before open.';
    case AppErrorCodes.unsupportedOperation:
      return 'This command is not available for the selected platform/device.';
    case AppErrorCodes.notImplemented:
      return 'This command is part of the planned API but is not implemented yet.';
    case AppErrorCodes.commandFailed:
      return 'Retry with --debug and inspect diagnostics log for details.';
    case AppErrorCodes.unauthorized:
      return 'Refresh daemon metadata and retry the command.';
    default:
      return 'Retry with --debug and inspect diagnostics log for details.';
  }
}
