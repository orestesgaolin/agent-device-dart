// Port of agent-device/src/platforms/ios/screenshot.ts (MVP subset).
//
// The TS source has a rich screenshot pipeline (status-bar overlay,
// diff-region overlays, scale knobs) — the Dart MVP keeps just the
// `simctl io <udid> screenshot <path>` invocation. Overlays land with
// Phase 10.
library;

import 'dart:io';

import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';

import 'simctl.dart';

/// Capture a PNG of [udid]'s current screen to [outPath]. Throws if the
/// simulator isn't booted.
Future<void> screenshotIos(String udid, String outPath) async {
  await runCmd(
    'xcrun',
    buildSimctlArgs(['io', udid, 'screenshot', outPath]),
    const ExecOptions(timeoutMs: 30000),
  );
  // simctl writes the file even when the UDID is unknown (zero bytes).
  // Validate that we actually got a PNG back.
  final file = File(outPath);
  if (!await file.exists()) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'simctl screenshot did not produce a file at $outPath',
      details: {'udid': udid, 'outPath': outPath},
    );
  }
  final len = await file.length();
  if (len < 8) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'simctl screenshot wrote $len bytes to $outPath (expected a PNG)',
      details: {'udid': udid, 'outPath': outPath, 'size': len},
    );
  }
}
