// Port of agent-device/src/platforms/android/snapshot.ts

import '../../snapshot/snapshot.dart';
import '../../utils/errors.dart';
import '../../utils/exec.dart';
import '../../utils/retry.dart';
import '../../utils/scrollable.dart';
import 'adb.dart';
import 'scroll_hints.dart';
import 'ui_hierarchy.dart';

const _uiHierarchyDumpTimeoutMs = 8000;

/// Capture a device snapshot with optional filtering and hint enrichment.
///
/// Dumps the Android UIAutomator hierarchy, parses it into RawSnapshotNode
/// objects, and applies scroll-hint analysis to detect hidden content.
/// When [options.interactiveOnly] is true, filters to interactive elements
/// and applies both native scroll hints and presentation-based hints.
Future<
  ({
    List<RawSnapshotNode> nodes,
    bool? truncated,
    AndroidSnapshotAnalysis analysis,
  })
>
snapshotAndroid(
  String serial, {
  SnapshotOptions options = const SnapshotOptions(),
}) async {
  final xml = await dumpUiHierarchy(serial);

  if (!(options.interactiveOnly ?? false)) {
    final parsed = parseUiHierarchy(xml, 800, options);
    final nativeHints = await _deriveScrollableContentHintsIfNeeded(
      serial,
      parsed.nodes,
    );
    _applyHiddenContentHintsToNodes(nativeHints, parsed.nodes);
    return parsed;
  }

  final tree = parseUiHierarchyTree(xml);
  final fullSnapshot = buildUiHierarchySnapshot(
    tree,
    800,
    SnapshotOptions(
      interactiveOnly: false,
      compact: options.compact,
      depth: options.depth,
      scope: options.scope,
      raw: options.raw,
    ),
  );

  final interactiveSnapshot = buildUiHierarchySnapshot(tree, 800, options);
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
    // TODO(port): resolved in Wave C
    // const presentationHints = deriveMobileSnapshotHiddenContentHints(
    //   attachRefs(fullSnapshot.nodes),
    // );
    // _applyHiddenContentHintsToInteractiveNodes(
    //   presentationHints,
    //   fullSnapshot,
    //   interactiveSnapshot,
    // );
  }

  return (
    nodes: interactiveSnapshot.nodes,
    truncated: interactiveSnapshot.truncated,
    analysis: interactiveSnapshot.analysis,
  );
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

/// Apply hidden content hints to all nodes.
///
/// TODO(port): apply `hint.hiddenContentAbove` / `hiddenContentBelow` once
/// [RawSnapshotNode] supports mutation (copy-with pattern or mutable fields).
/// The ported model is immutable — both hint flags flow through the builders
/// at construction time instead. Keeping this function as a no-op shell so
/// call-sites keep a stable seam.
void _applyHiddenContentHintsToNodes(
  Map<int, HiddenContentHint> hintsByIndex,
  List<RawSnapshotNode> nodes,
) {
  // Intentional no-op: arguments retained so call-sites keep the correct
  // shape when mutation support is added.
  if (hintsByIndex.isEmpty || nodes.isEmpty) return;
}

/// Apply hidden content hints to nodes in the interactive snapshot.
///
/// TODO(port): same blocker as [_applyHiddenContentHintsToNodes] — mutation
/// of [RawSnapshotNode] isn't supported in the Dart port yet, so this stays
/// a no-op shell. Keep the function + argument list to preserve the call
/// seam; fill in the body when the snapshot model gets mutable/copy-with
/// support.
void _applyHiddenContentHintsToInteractiveNodes(
  Map<int, HiddenContentHint> hintsByFullNodeIndex,
  AndroidBuiltSnapshot fullSnapshot,
  AndroidBuiltSnapshot interactiveSnapshot,
) {
  if (hintsByFullNodeIndex.isEmpty ||
      fullSnapshot.sourceNodes.isEmpty ||
      interactiveSnapshot.sourceNodes.isEmpty) {
    return;
  }
  // Intentional no-op until RawSnapshotNode is mutable.
}
