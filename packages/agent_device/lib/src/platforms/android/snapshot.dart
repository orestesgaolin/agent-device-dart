// Port of agent-device/src/platforms/android/snapshot.ts

import 'dart:io' show stderr, Platform;

import '../../snapshot/snapshot.dart';
import '../../utils/errors.dart'
    show AppError, AppErrorCodes, agentDeviceVerbose;
import '../../utils/exec.dart';
import '../../utils/mobile_snapshot_semantics.dart';
import '../../utils/retry.dart';
import '../../utils/scrollable.dart';
import 'adb.dart';
import 'scroll_hints.dart';
import 'snapshot_helper_artifact.dart';
import 'snapshot_helper_capture.dart';
import 'snapshot_helper_install.dart';
import 'snapshot_helper_types.dart';
import 'snapshot_types.dart';
import 'ui_hierarchy.dart';

const _uiHierarchyDumpTimeoutMs = 8000;
const _helperInstallTimeoutMs = 30000;
const _helperCommandTimeoutMs =
    _uiHierarchyDumpTimeoutMs + androidSnapshotHelperCommandOverheadMs;

/// Options for Android snapshot capture.
class AndroidSnapshotOptions {
  final SnapshotOptions snapshot;
  final AndroidSnapshotHelperArtifact? helperArtifact;
  final AndroidSnapshotHelperInstallPolicy helperInstallPolicy;
  final AndroidAdbExecutor? helperAdb;

  const AndroidSnapshotOptions({
    this.snapshot = const SnapshotOptions(),
    this.helperArtifact,
    this.helperInstallPolicy =
        AndroidSnapshotHelperInstallPolicy.missingOrOutdated,
    this.helperAdb,
  });
}

/// Capture a device snapshot with optional filtering and hint enrichment.
///
/// Tries the snapshot helper first (if available), falling back to plain
/// uiautomator dump. Returns both the nodes and backend metadata indicating
/// which path was taken.
///
/// Port of `snapshotAndroid` in `snapshot.ts`.
Future<
  ({
    List<RawSnapshotNode> nodes,
    bool? truncated,
    AndroidSnapshotAnalysis analysis,
    AndroidSnapshotBackendMetadata androidSnapshot,
  })
>
snapshotAndroid(
  String serial, {
  AndroidSnapshotOptions options = const AndroidSnapshotOptions(),
}) async {
  final capture = await _captureAndroidUiHierarchy(serial, options);
  final xml = capture.xml;
  final snapshotOptions = options.snapshot;

  if (!(snapshotOptions.interactiveOnly ?? false)) {
    final parsed = parseUiHierarchy(
      xml,
      androidSnapshotMaxNodes,
      snapshotOptions,
    );
    final nativeHints = await _deriveScrollableContentHintsIfNeeded(
      serial,
      parsed.nodes,
    );
    _applyHiddenContentHintsToNodes(nativeHints, parsed.nodes);
    return (
      nodes: parsed.nodes,
      truncated: parsed.truncated,
      analysis: parsed.analysis,
      androidSnapshot: capture.metadata,
    );
  }

  final tree = parseUiHierarchyTree(xml);
  final fullSnapshot = buildUiHierarchySnapshot(
    tree,
    androidSnapshotMaxNodes,
    SnapshotOptions(
      interactiveOnly: false,
      compact: snapshotOptions.compact,
      depth: snapshotOptions.depth,
      scope: snapshotOptions.scope,
      raw: snapshotOptions.raw,
    ),
  );

  final interactiveSnapshot = buildUiHierarchySnapshot(
    tree,
    androidSnapshotMaxNodes,
    snapshotOptions,
  );
  final nativeHints = await _deriveScrollableContentHintsIfNeeded(
    serial,
    fullSnapshot.nodes,
  );

  _applyHiddenContentHintsToInteractiveNodes(
    nativeHints,
    fullSnapshot,
    interactiveSnapshot,
  );

  if (nativeHints.isEmpty) {
    final presentationHints = deriveMobileSnapshotHiddenContentHints(
      attachRefs(fullSnapshot.nodes),
    );
    _applyHiddenContentHintsToInteractiveNodes(
      presentationHints,
      fullSnapshot,
      interactiveSnapshot,
    );
  }

  return (
    nodes: interactiveSnapshot.nodes,
    truncated: interactiveSnapshot.truncated,
    analysis: interactiveSnapshot.analysis,
    androidSnapshot: capture.metadata,
  );
}

// ---------------------------------------------------------------------------
// Helper capture orchestration
// ---------------------------------------------------------------------------

Future<({String xml, AndroidSnapshotBackendMetadata metadata})>
_captureAndroidUiHierarchy(
  String serial,
  AndroidSnapshotOptions options,
) async {
  final helper = await _resolveAndroidSnapshotHelperArtifact(
    options.helperArtifact,
  );
  final artifact = helper.$1;

  if (artifact != null) {
    try {
      _log(
        '[snapshot] using helper v${artifact.manifest.version} '
        '(${artifact.apkPath})',
      );
      final adb = options.helperAdb ?? _createDeviceAdbExecutor(serial);
      final install = await ensureAndroidSnapshotHelper(
        adb: adb,
        artifact: artifact,
        installPolicy: options.helperInstallPolicy,
        timeoutMs: _helperInstallTimeoutMs,
      );
      _log(
        '[snapshot] helper install: ${install.reason}'
        '${install.installed ? ' (freshly installed)' : ' (already on device)'}',
      );
      final capture = await captureAndroidSnapshotWithHelper(
        AndroidSnapshotHelperCaptureOptions(
          adb: adb,
          packageName: artifact.manifest.packageName,
          instrumentationRunner: artifact.manifest.instrumentationRunner,
          waitForIdleTimeoutMs: androidSnapshotHelperWaitForIdleTimeoutMs,
          timeoutMs: _uiHierarchyDumpTimeoutMs,
          commandTimeoutMs: _helperCommandTimeoutMs,
        ),
      );
      _log(
        '[snapshot] helper capture: '
        'mode=${capture.metadata.captureMode} '
        'windows=${capture.metadata.windowCount} '
        'nodes=${capture.metadata.nodeCount} '
        '${capture.metadata.elapsedMs}ms',
      );
      return (
        xml: capture.xml,
        metadata: AndroidSnapshotBackendMetadata(
          backend: 'android-helper',
          helperVersion: artifact.manifest.version,
          helperApiVersion: capture.metadata.helperApiVersion,
          installReason: install.reason,
          waitForIdleTimeoutMs: capture.metadata.waitForIdleTimeoutMs,
          timeoutMs: capture.metadata.timeoutMs,
          maxDepth: capture.metadata.maxDepth,
          maxNodes: capture.metadata.maxNodes,
          rootPresent: capture.metadata.rootPresent,
          captureMode: capture.metadata.captureMode,
          windowCount: capture.metadata.windowCount,
          nodeCount: capture.metadata.nodeCount,
          helperTruncated: capture.metadata.truncated,
          elapsedMs: capture.metadata.elapsedMs,
        ),
      );
    } catch (error) {
      final reason = (error is AppError) ? error.message : error.toString();
      _log('[snapshot] helper failed, falling back to uiautomator: $reason');
      return _captureStockUiHierarchy(serial, fallbackReason: reason);
    }
  }

  _log(
    '[snapshot] no helper artifact available'
    '${helper.$2 != null ? ' (${helper.$2})' : ''}, using uiautomator',
  );
  return _captureStockUiHierarchy(serial, fallbackReason: helper.$2);
}

Future<(AndroidSnapshotHelperArtifact?, String?)>
_resolveAndroidSnapshotHelperArtifact(
  AndroidSnapshotHelperArtifact? explicitArtifact,
) async {
  if (explicitArtifact != null) return (explicitArtifact, null);

  final bundled = await resolveBundledAndroidSnapshotHelperArtifact();
  if (bundled != null) return (bundled, null);
  return (null, null);
}

Future<({String xml, AndroidSnapshotBackendMetadata metadata})>
_captureStockUiHierarchy(String serial, {String? fallbackReason}) async {
  return (
    xml: await dumpUiHierarchy(serial),
    metadata: AndroidSnapshotBackendMetadata(
      backend: 'uiautomator-dump',
      fallbackReason: fallbackReason,
    ),
  );
}

AndroidAdbExecutor _createDeviceAdbExecutor(String serial) {
  return (
    List<String> args, {
    bool allowFailure = false,
    int? timeoutMs,
  }) async {
    final result = await runCmd(
      'adb',
      adbArgs(serial, args),
      ExecOptions(allowFailure: allowFailure, timeoutMs: timeoutMs),
    );
    return AdbResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  };
}

/// Derive scroll hints if any scrollable elements are present.
///
/// Checks if the snapshot contains scrollable nodes. If so, fetches
/// the activity view tree and analyzes it to infer hidden content.
Future<Map<int, HiddenContentHint>> _deriveScrollableContentHintsIfNeeded(
  String serial,
  List<RawSnapshotNode> nodes,
) async {
  if (!nodes.any((node) => isScrollableType(node.type))) {
    return {};
  }

  final activityTopDump = await _dumpActivityTop(serial);
  if (activityTopDump == null) {
    return {};
  }

  return deriveAndroidScrollableContentHints(nodes, activityTopDump);
}

/// Dump Android UI hierarchy via UIAutomator.
///
/// Attempts to stream XML directly to stdout (preferred), falling back
/// to dumping to /sdcard and reading back if needed. Retries on transient
/// ADB errors (offline, transport errors, timeouts).
Future<String> dumpUiHierarchy(String serial) async {
  try {
    return await withRetry(
      () => _dumpUiHierarchyOnce(serial),
      shouldRetry: (err, _) => _isRetryableAdbError(err),
    );
  } catch (error) {
    if (_isUiHierarchyDumpTimeout(error)) {
      const hint =
          'If the app has looping animations, use screenshot as visual truth, try settings animations off, then retry snapshot. Stock Android UIAutomator may still time out on app-owned infinite animations.';
      throw AppError(
        AppErrorCodes.commandFailed,
        'Android UI hierarchy dump timed out while waiting for the UI to become idle. $hint',
        details: {
          ...((error is AppError) ? (error.details ?? {}) : {}),
          'hint': hint,
        },
        cause: error,
      );
    }
    rethrow;
  }
}

/// Dump UI hierarchy once, with fallback strategy.
///
/// Preferred: stream XML directly to stdout via /dev/tty.
/// Fallback: dump to /sdcard, then cat back.
Future<String> _dumpUiHierarchyOnce(String serial) async {
  // Preferred: stream XML directly to stdout, avoiding file I/O race conditions.
  final streamed = await runCmd(
    'adb',
    adbArgs(serial, ['exec-out', 'uiautomator', 'dump', '/dev/tty']),
    const ExecOptions(allowFailure: true, timeoutMs: _uiHierarchyDumpTimeoutMs),
  );

  final fromStream = _extractUiDumpXml(streamed.stdout, streamed.stderr);
  if (fromStream != null) return fromStream;

  // If the JVM was killed (leaked UiAutomationService registration, OOM,
  // framework policy), adb returns exit 0 with the shell's "Killed" message
  // in stdout and no XML. Don't waste another 8s on the fallback — it will
  // fail the same way. Surface an actionable error instead.
  if (_looksLikeUiAutomatorKilled(streamed.stdout, streamed.stderr)) {
    throw _uiAutomatorKilledError(streamed.stdout, streamed.stderr);
  }

  // Fallback: dump to file and read back.
  const dumpPath = '/sdcard/window_dump.xml';
  final dumpResult = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'uiautomator', 'dump', dumpPath]),
    const ExecOptions(allowFailure: true, timeoutMs: _uiHierarchyDumpTimeoutMs),
  );

  if (_looksLikeUiAutomatorKilled(dumpResult.stdout, dumpResult.stderr)) {
    throw _uiAutomatorKilledError(dumpResult.stdout, dumpResult.stderr);
  }

  final actualPath = _resolveDumpPath(
    dumpPath,
    dumpResult.stdout,
    dumpResult.stderr,
  );

  final result = await runCmd(
    'adb',
    adbArgs(serial, ['shell', 'cat', actualPath]),
    const ExecOptions(allowFailure: true),
  );

  final xml = _extractUiDumpXml(result.stdout, result.stderr);
  if (xml == null) {
    final stderr = result.stderr.toLowerCase();
    // When the preceding uiautomator invocation was killed, the dump file
    // was never written. `cat` reports "No such file or directory".
    if (stderr.contains('no such file') ||
        stderr.contains('cannot open') ||
        result.exitCode != 0) {
      throw _uiAutomatorKilledError(
        '${dumpResult.stdout}\n${result.stdout}',
        '${dumpResult.stderr}\n${result.stderr}',
      );
    }
    throw AppError(
      AppErrorCodes.commandFailed,
      'uiautomator dump did not return XML',
      details: {'stdout': result.stdout, 'stderr': result.stderr},
    );
  }

  return xml;
}

/// Detect the "UiAutomationService already registered" failure mode where
/// the `uiautomator` JVM is killed by the Android runtime before it can
/// produce any XML. The shell prints "Killed" on its own stderr and adb
/// still exits 0, so the failure is invisible to the exit-code path.
bool _looksLikeUiAutomatorKilled(String stdout, String stderr) {
  final combined = '$stdout\n$stderr';
  if (combined.contains('<hierarchy')) return false;
  return RegExp(r'\bKilled\b').hasMatch(combined);
}

/// Build an [AppError] that points the user at the most common recovery
/// (cold-restart the AVD / reboot the device) and records the captured
/// output so the diagnostic path remains intact.
AppError _uiAutomatorKilledError(String stdout, String stderr) {
  const hint =
      'The device\'s uiautomator was killed before producing XML (usually a '
      'leaked UiAutomationService registration: "UiAutomationService ... '
      'already registered!"). Cold-restart the emulator (`adb -s <serial> '
      'emu kill` + relaunch the AVD) or reboot the device. On rootable '
      'images, `adb root && adb shell stop && adb shell start` also works.';
  return AppError(
    AppErrorCodes.commandFailed,
    'Android uiautomator dump failed: device killed the process. $hint',
    details: {
      'stdout': stdout,
      'stderr': stderr,
      'hint': hint,
      'reason': 'uiautomator_killed',
    },
  );
}

/// Resolve the actual dump path from uiautomator output.
///
/// Parses `dumped to: <path>` from stdout/stderr, falling back to
/// the provided default path.
String _resolveDumpPath(String defaultPath, String stdout, String stderr) {
  final text = '$stdout\n$stderr';
  final match = RegExp(
    r'dumped to:\s*(\S+)',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(1) ?? defaultPath;
}

/// Extract XML from uiautomator output.
///
/// Looks for either an XML declaration or `<hierarchy>` tag and extracts
/// everything from there until the closing `</hierarchy>` tag.
String? _extractUiDumpXml(String stdout, String stderr) {
  final text = '$stdout\n$stderr';

  final start = text.indexOf('<?xml');
  final hierarchyStart = start >= 0 ? start : text.indexOf('<hierarchy');

  if (hierarchyStart < 0) return null;

  final end = text.lastIndexOf('</hierarchy>');
  if (end < 0 || end < hierarchyStart) return null;

  final xml = text
      .substring(hierarchyStart, end + '</hierarchy>'.length)
      .trim();

  return xml.isNotEmpty ? xml : null;
}

/// Check if an error is retryable (transient ADB issue).
bool _isRetryableAdbError(Object err) {
  if (err is! AppError) return false;
  if (err.code != AppErrorCodes.commandFailed) return false;

  final rawStderr = err.details?['stderr'];
  final stderr = (rawStderr is String ? rawStderr : '').toLowerCase();

  return stderr.contains('device offline') ||
      stderr.contains('device not found') ||
      stderr.contains('transport error') ||
      stderr.contains('connection reset') ||
      stderr.contains('broken pipe') ||
      stderr.contains('timed out') ||
      stderr.contains('no such file or directory');
}

/// Check if an error is a UI hierarchy dump timeout.
bool _isUiHierarchyDumpTimeout(Object err) {
  if (err is! AppError) return false;
  if (err.code != AppErrorCodes.commandFailed) return false;

  final timeoutMs = err.details?['timeoutMs'];
  if (timeoutMs is! int) return false;

  final cmd = err.details?['cmd'];
  if (cmd != 'adb') return false;

  final rawArgs = err.details?['args'];
  final args = <String>[];
  if (rawArgs is List) {
    args.addAll(rawArgs.map((e) => e.toString()));
  } else if (rawArgs is String) {
    args.addAll(rawArgs.split(RegExp(r'\s+')));
  }

  return args.contains('uiautomator') && args.contains('dump');
}

/// Dump the current activity's view tree via dumpsys.
///
/// Used to infer native scroll positions and hidden content for
/// scrollable snapshot nodes. Returns null on error.
Future<String?> _dumpActivityTop(String serial) async {
  try {
    final result = await runCmd(
      'adb',
      adbArgs(serial, ['shell', 'dumpsys', 'activity', 'top']),
      const ExecOptions(allowFailure: true, timeoutMs: 8000),
    );
    final text = '${result.stdout}\n${result.stderr}'.trim();
    return text.isNotEmpty ? text : null;
  } catch (_) {
    return null;
  }
}

/// Apply hidden content hints to all nodes by index.
///
/// Iterates the hints map and writes each hint's flags onto the matching node.
/// [RawSnapshotNode.hiddenContentAbove] and [RawSnapshotNode.hiddenContentBelow]
/// are non-final, so direct mutation is safe.
void _applyHiddenContentHintsToNodes(
  Map<int, HiddenContentHint> hintsByIndex,
  List<RawSnapshotNode> nodes,
) {
  if (hintsByIndex.isEmpty || nodes.isEmpty) return;
  for (final entry in hintsByIndex.entries) {
    final index = entry.key;
    final hint = entry.value;
    if (index < 0 || index >= nodes.length) continue;
    final node = nodes[index];
    if (hint.hiddenContentAbove) node.hiddenContentAbove = true;
    if (hint.hiddenContentBelow) node.hiddenContentBelow = true;
  }
}

/// Apply hidden content hints to nodes in the interactive snapshot.
///
/// Both snapshots come from the same parsed hierarchy tree, so source node
/// identity is the stable bridge between full geometry context and the pruned
/// interactive output.  We build a reverse map from [AndroidUiHierarchy]
/// object identity to the corresponding interactive [RawSnapshotNode], then
/// look up each hinted full-snapshot source node via that map.
void _applyHiddenContentHintsToInteractiveNodes(
  Map<int, HiddenContentHint> hintsByFullNodeIndex,
  AndroidBuiltSnapshot fullSnapshot,
  AndroidBuiltSnapshot interactiveSnapshot,
) {
  if (hintsByFullNodeIndex.isEmpty) return;

  // Map source node object identity → interactive RawSnapshotNode.
  final interactiveNodesBySource = <AndroidUiHierarchy, RawSnapshotNode>{};
  for (var i = 0; i < interactiveSnapshot.sourceNodes.length; i++) {
    final sourceNode = interactiveSnapshot.sourceNodes[i];
    if (i < interactiveSnapshot.nodes.length) {
      interactiveNodesBySource[sourceNode] = interactiveSnapshot.nodes[i];
    }
  }

  for (final entry in hintsByFullNodeIndex.entries) {
    final fullIndex = entry.key;
    final hint = entry.value;
    if (fullIndex < 0 || fullIndex >= fullSnapshot.sourceNodes.length) {
      continue;
    }
    final sourceNode = fullSnapshot.sourceNodes[fullIndex];
    final interactiveNode = interactiveNodesBySource[sourceNode];
    if (interactiveNode == null) continue;

    if (hint.hiddenContentAbove) interactiveNode.hiddenContentAbove = true;
    if (hint.hiddenContentBelow) interactiveNode.hiddenContentBelow = true;
  }
}

bool get _verbose =>
    agentDeviceVerbose ||
    Platform.environment['AGENT_DEVICE_ANDROID_SNAPSHOT_DEBUG'] == '1';

void _log(String message) {
  if (_verbose) stderr.writeln(message);
}
