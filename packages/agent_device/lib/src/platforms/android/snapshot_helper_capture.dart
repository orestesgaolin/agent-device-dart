// Port of agent-device/src/platforms/android/snapshot-helper-capture.ts

import 'dart:convert';

import '../../snapshot/snapshot.dart';
import '../../utils/errors.dart';
import 'snapshot_helper_types.dart';
import 'snapshot_types.dart';
import 'ui_hierarchy.dart';

/// Raw base64-encoded chunk from the instrumentation status stream.
class _AndroidSnapshotHelperChunk {
  final int? index;
  final int? count;
  final String payloadBase64;

  const _AndroidSnapshotHelperChunk({
    required this.index,
    required this.count,
    required this.payloadBase64,
  });
}

/// Mutable accumulator while parsing instrumentation output lines.
class _AndroidInstrumentationRecordState {
  final List<Map<String, String>> status = [];
  final List<Map<String, String>> results = [];
  Map<String, String>? currentStatus;
  Map<String, String>? currentResult;
}

/// Run the helper APK via `adb shell am instrument` and return the captured
/// XML + metadata.
///
/// Port of `captureAndroidSnapshotWithHelper` in
/// `snapshot-helper-capture.ts`.
Future<AndroidSnapshotHelperOutput> captureAndroidSnapshotWithHelper(
  AndroidSnapshotHelperCaptureOptions options,
) async {
  final waitForIdleTimeoutMs =
      options.waitForIdleTimeoutMs ?? androidSnapshotHelperWaitForIdleTimeoutMs;
  final timeoutMs = options.timeoutMs ?? 8000;
  final commandTimeoutMs =
      options.commandTimeoutMs ??
      timeoutMs + androidSnapshotHelperCommandOverheadMs;
  final maxDepth = options.maxDepth ?? 128;
  final maxNodes = options.maxNodes ?? 5000;
  final packageName = options.packageName ?? androidSnapshotHelperPackage;
  final runner =
      options.instrumentationRunner ?? '$packageName/.SnapshotInstrumentation';

  final args = [
    'shell',
    'am',
    'instrument',
    '-w',
    '-e',
    'waitForIdleTimeoutMs',
    '$waitForIdleTimeoutMs',
    '-e',
    'timeoutMs',
    '$timeoutMs',
    '-e',
    'maxDepth',
    '$maxDepth',
    '-e',
    'maxNodes',
    '$maxNodes',
    runner,
  ];

  final result = await options.adb(
    args,
    allowFailure: true,
    timeoutMs: commandTimeoutMs,
  );

  AndroidSnapshotHelperOutput output;
  try {
    // The helper can report structured ok=false details even when am exits non-zero.
    output = parseAndroidSnapshotHelperOutput(
      '${result.stdout}\n${result.stderr}',
    );
  } catch (error) {
    throw AppError(
      AppErrorCodes.commandFailed,
      result.exitCode == 0
          ? 'Android snapshot helper output could not be parsed'
          : 'Android snapshot helper failed before returning parseable output',
      details: {
        'stdout': result.stdout,
        'stderr': result.stderr,
        'exitCode': result.exitCode,
      },
      cause: error,
    );
  }

  if (result.exitCode != 0) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Android snapshot helper failed',
      details: {
        'stdout': result.stdout,
        'stderr': result.stderr,
        'exitCode': result.exitCode,
        'helper': _metadataToMap(output.metadata),
      },
    );
  }

  return output;
}

/// Parse the raw text output from `adb shell am instrument` into structured
/// XML + metadata.
///
/// Port of `parseAndroidSnapshotHelperOutput`.
AndroidSnapshotHelperOutput parseAndroidSnapshotHelperOutput(String output) {
  final records = _parseInstrumentationRecords(output);
  final finalResult = _readFinalHelperResult(records.$1);
  final xml = _decodeHelperXml(_collectHelperChunks(records.$2), finalResult);
  return AndroidSnapshotHelperOutput(
    xml: xml,
    metadata: _readHelperMetadata(finalResult),
  );
}

/// Parse the captured XML and metadata into snapshot nodes.
///
/// Port of `parseAndroidSnapshotHelperXml`.
AndroidSnapshotHelperParsedSnapshot parseAndroidSnapshotHelperXml(
  String xml, {
  AndroidSnapshotHelperMetadata? metadata,
  SnapshotOptions options = const SnapshotOptions(),
  int maxNodes = androidSnapshotMaxNodes,
}) {
  metadata ??= const AndroidSnapshotHelperMetadata(
    outputFormat: androidSnapshotHelperOutputFormat,
  );
  final parsed = parseUiHierarchy(xml, maxNodes, options);
  return AndroidSnapshotHelperParsedSnapshot(
    nodes: parsed.nodes,
    truncated: parsed.truncated,
    analysis: parsed.analysis,
    metadata: metadata,
  );
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

List<_AndroidSnapshotHelperChunk> _collectHelperChunks(
  List<Map<String, String>> records,
) {
  return records
      .where(
        (record) =>
            record['agentDeviceProtocol'] == androidSnapshotHelperProtocol &&
            record['outputFormat'] == androidSnapshotHelperOutputFormat &&
            record.containsKey('payloadBase64'),
      )
      .map(
        (record) => _AndroidSnapshotHelperChunk(
          index: _readOptionalInt(record['chunkIndex']),
          count: _readOptionalInt(record['chunkCount']),
          payloadBase64: record['payloadBase64']!,
        ),
      )
      .toList();
}

Map<String, String> _readFinalHelperResult(List<Map<String, String>> records) {
  final finalResult = records.firstWhere(
    (record) => record['agentDeviceProtocol'] == androidSnapshotHelperProtocol,
    orElse: () => throw AppError(
      AppErrorCodes.commandFailed,
      'Android snapshot helper did not return a final result',
    ),
  );

  if (finalResult['ok'] != 'true') {
    throw AppError(
      AppErrorCodes.commandFailed,
      _readHelperErrorMessage(finalResult),
      details: {'errorType': finalResult['errorType'], 'helper': finalResult},
    );
  }

  return finalResult;
}

String _readHelperErrorMessage(Map<String, String> finalResult) {
  final message = finalResult['message'];
  if (message != null && message != 'null') return message;
  return finalResult['errorType'] ??
      'Android snapshot helper returned an error';
}

String _decodeHelperXml(
  List<_AndroidSnapshotHelperChunk> chunks,
  Map<String, String> finalResult,
) {
  if (chunks.isEmpty) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Android snapshot helper did not return XML chunks',
      details: {'helper': finalResult},
    );
  }

  final chunkCount = _validateChunkCount(chunks);
  final chunksByIndex = _indexChunks(chunks, chunkCount);
  final payloads = _readChunkPayloads(chunksByIndex, chunkCount);

  // Concatenate all byte payloads then decode as UTF-8 so multi-byte
  // characters that span chunk boundaries are reconstructed correctly.
  final totalLength = payloads.fold<int>(0, (sum, b) => sum + b.length);
  final combined = List<int>.filled(totalLength, 0);
  var offset = 0;
  for (final bytes in payloads) {
    combined.setRange(offset, offset + bytes.length, bytes);
    offset += bytes.length;
  }

  final xml = utf8.decode(combined);

  if (!xml.contains('<hierarchy') || !xml.contains('</hierarchy>')) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Android snapshot helper output did not contain XML',
      details: {'xml': xml},
    );
  }

  return xml;
}

int _validateChunkCount(List<_AndroidSnapshotHelperChunk> chunks) {
  final chunkCount = chunks[0].count ?? chunks.length;
  if (chunkCount < 1 ||
      chunks.length != chunkCount ||
      chunks.any((chunk) => chunk.count != chunkCount)) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Android snapshot helper returned incomplete XML chunks',
      details: {'expectedChunks': chunkCount, 'actualChunks': chunks.length},
    );
  }
  return chunkCount;
}

Map<int, String> _indexChunks(
  List<_AndroidSnapshotHelperChunk> chunks,
  int chunkCount,
) {
  final chunksByIndex = <int, String>{};
  for (final chunk in chunks) {
    final index = chunk.index;
    if (index == null || index < 0 || index >= chunkCount) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'Android snapshot helper returned invalid chunk index',
        details: {'chunkIndex': index, 'expectedChunks': chunkCount},
      );
    }
    if (chunksByIndex.containsKey(index)) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'Android snapshot helper returned duplicate XML chunks',
        details: {'chunkIndex': index},
      );
    }
    chunksByIndex[index] = chunk.payloadBase64;
  }
  return chunksByIndex;
}

List<List<int>> _readChunkPayloads(
  Map<int, String> chunksByIndex,
  int chunkCount,
) {
  final payloads = <List<int>>[];
  for (var i = 0; i < chunkCount; i++) {
    final payloadBase64 = chunksByIndex[i];
    if (payloadBase64 == null) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'Android snapshot helper returned incomplete XML chunks',
        details: {'missingChunkIndex': i, 'expectedChunks': chunkCount},
      );
    }
    payloads.add(base64.decode(payloadBase64));
  }
  return payloads;
}

AndroidSnapshotHelperMetadata _readHelperMetadata(
  Map<String, String> finalResult,
) {
  return AndroidSnapshotHelperMetadata(
    helperApiVersion: finalResult['helperApiVersion'],
    outputFormat: androidSnapshotHelperOutputFormat,
    waitForIdleTimeoutMs: _readOptionalInt(finalResult['waitForIdleTimeoutMs']),
    timeoutMs: _readOptionalInt(finalResult['timeoutMs']),
    maxDepth: _readOptionalInt(finalResult['maxDepth']),
    maxNodes: _readOptionalInt(finalResult['maxNodes']),
    rootPresent: _readOptionalBool(finalResult['rootPresent']),
    captureMode: _readOptionalCaptureMode(finalResult['captureMode']),
    windowCount: _readOptionalInt(finalResult['windowCount']),
    nodeCount: _readOptionalInt(finalResult['nodeCount']),
    truncated: _readOptionalBool(finalResult['truncated']),
    elapsedMs: _readOptionalInt(finalResult['elapsedMs']),
  );
}

String? _readOptionalCaptureMode(String? value) {
  if (value == 'interactive-windows' || value == 'active-window') return value;
  return null;
}

/// Parse the raw `am instrument` output into status and result records.
///
/// Returns `(results, status)` — note reversed order to mirror the TS
/// destructuring that returns `{ status, results }`.
(List<Map<String, String>> results, List<Map<String, String>> status)
_parseInstrumentationRecords(String output) {
  final state = _AndroidInstrumentationRecordState();

  for (final line in output.split(RegExp(r'\r?\n'))) {
    _readInstrumentationRecordLine(line, state);
  }
  _flushInstrumentationRecords(state);

  return (state.results, state.status);
}

void _readInstrumentationRecordLine(
  String line,
  _AndroidInstrumentationRecordState state,
) {
  if (line.startsWith('INSTRUMENTATION_STATUS: ')) {
    state.currentStatus ??= {};
    _readKeyValue(
      line.substring('INSTRUMENTATION_STATUS: '.length),
      state.currentStatus!,
    );
    return;
  }
  if (line.startsWith('INSTRUMENTATION_STATUS_CODE: ')) {
    _flushStatusRecord(state);
    return;
  }
  if (line.startsWith('INSTRUMENTATION_RESULT: ')) {
    state.currentResult ??= {};
    _readKeyValue(
      line.substring('INSTRUMENTATION_RESULT: '.length),
      state.currentResult!,
    );
    return;
  }
  if (line.startsWith('INSTRUMENTATION_CODE: ')) {
    _flushResultRecord(state);
  }
}

void _flushInstrumentationRecords(_AndroidInstrumentationRecordState state) {
  _flushStatusRecord(state);
  _flushResultRecord(state);
}

void _flushStatusRecord(_AndroidInstrumentationRecordState state) {
  final current = state.currentStatus;
  if (current != null) {
    state.status.add(current);
    state.currentStatus = null;
  }
}

void _flushResultRecord(_AndroidInstrumentationRecordState state) {
  final current = state.currentResult;
  if (current != null) {
    state.results.add(current);
    state.currentResult = null;
  }
}

void _readKeyValue(String line, Map<String, String> target) {
  final separator = line.indexOf('=');
  if (separator < 0) return;
  target[line.substring(0, separator)] = line.substring(separator + 1);
}

int? _readOptionalInt(String? value) {
  if (value == null) return null;
  final parsed = int.tryParse(value) ?? double.tryParse(value)?.toInt();
  return parsed;
}

bool? _readOptionalBool(String? value) {
  if (value == 'true') return true;
  if (value == 'false') return false;
  return null;
}

Map<String, Object?> _metadataToMap(AndroidSnapshotHelperMetadata m) => {
  'helperApiVersion': m.helperApiVersion,
  'outputFormat': m.outputFormat,
  'waitForIdleTimeoutMs': m.waitForIdleTimeoutMs,
  'timeoutMs': m.timeoutMs,
  'maxDepth': m.maxDepth,
  'maxNodes': m.maxNodes,
  'rootPresent': m.rootPresent,
  'captureMode': m.captureMode,
  'windowCount': m.windowCount,
  'nodeCount': m.nodeCount,
  'truncated': m.truncated,
  'elapsedMs': m.elapsedMs,
};
