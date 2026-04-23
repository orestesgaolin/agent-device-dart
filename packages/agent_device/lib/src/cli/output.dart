// Output formatting for the `agent-device` CLI.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/utils/errors.dart';

/// Print a successful command result. In `--json` mode, emits
/// `{"success":true,"data":...}`; otherwise prints the result of
/// [humanFormat] (which is given the raw data).
void printResult(
  Object? data, {
  required bool asJson,
  String Function(Object? data)? humanFormat,
}) {
  if (asJson) {
    stdout.writeln(jsonEncode({'success': true, 'data': data}));
    return;
  }
  if (humanFormat != null) {
    final text = humanFormat(data);
    if (text.isNotEmpty) stdout.writeln(text);
    return;
  }
  // Default human rendering: jsonEncode with indenting.
  if (data != null) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
  }
}

/// Print a short success acknowledgement in human mode (matches the TS
/// CLI's "printed ack for mutating commands" behavior). No-op in JSON
/// mode since the JSON envelope already signals success.
void printAck(String message, {required bool asJson}) {
  if (asJson) return;
  stdout.writeln(message);
}

/// Print an error. JSON mode emits `{"success":false,"error":...}`; human
/// mode emits a multi-line message to stderr with the hint, diagnostic
/// id, and log path when available.
void printError(
  Object err, {
  required bool asJson,
  bool showDetails = false,
  String? diagnosticId,
  String? logPath,
}) {
  final normalized = normalizeError(
    err,
    diagnosticId: diagnosticId,
    logPath: logPath,
  );
  if (asJson) {
    stdout.writeln(
      jsonEncode({'success': false, 'error': normalized.toJson()}),
    );
    return;
  }
  final buf = StringBuffer()
    ..writeln('Error: ${normalized.message}')
    ..writeln('  code: ${normalized.code}');
  if (normalized.hint != null) buf.writeln('  hint: ${normalized.hint}');
  if (normalized.diagnosticId != null) {
    buf.writeln('  diagnosticId: ${normalized.diagnosticId}');
  }
  if (normalized.logPath != null) {
    buf.writeln('  logPath: ${normalized.logPath}');
  }
  if (showDetails && normalized.details != null) {
    buf.writeln(
      '  details: ${const JsonEncoder.withIndent('  ').convert(normalized.details)}',
    );
  }
  stderr.write(buf.toString());
}
