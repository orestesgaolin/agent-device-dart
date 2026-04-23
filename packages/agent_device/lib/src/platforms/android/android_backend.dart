// Port of agent-device/src/platforms/android/index.ts

import 'package:agent_device/src/backend/backend_exports.dart';
import 'package:agent_device/src/platforms/android/screenshot.dart';
import 'package:agent_device/src/platforms/android/snapshot.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:agent_device/src/utils/errors.dart';

/// Android platform backend implementation.
///
/// Extends the abstract Backend class and provides concrete implementations
/// for Android-specific operations by delegating to module-level functions.
/// This is the public entry point for Android backend capabilities.
class AndroidBackend extends Backend {
  AndroidBackend();

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.android;

  @override
  BackendCapabilitySet? get capabilities => null;

  @override
  BackendEscapeHatches? get escapeHatches => null;

  @override
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  ) async {
    final opts = SnapshotOptions(
      interactiveOnly: options?.interactiveOnly,
      compact: options?.compact,
      depth: options?.depth,
      scope: options?.scope,
      raw: options?.raw,
    );
    final result = await snapshotAndroid(ctx.appId ?? '', options: opts);

    return BackendSnapshotResult(
      nodes: result.nodes,
      truncated: result.truncated,
      analysis: BackendSnapshotAnalysis(
        rawNodeCount: result.analysis.rawNodeCount,
        maxDepth: result.analysis.maxDepth,
      ),
    );
  }

  @override
  Future<BackendScreenshotResult?> captureScreenshot(
    BackendCommandContext ctx,
    String outPath,
    BackendScreenshotOptions? options,
  ) async {
    await screenshotAndroid(ctx.appId ?? '', outPath);
    return BackendScreenshotResult(path: outPath);
  }

  @override
  Future<BackendReadTextResult> readText(
    BackendCommandContext ctx,
    Object node,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'readText is not supported on Android',
    );
  }

  @override
  Future<BackendFindTextResult> findText(
    BackendCommandContext ctx,
    String text,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'findText is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> tap(
    BackendCommandContext ctx,
    Point point,
    BackendTapOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'tap is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> fill(
    BackendCommandContext ctx,
    Point point,
    String text,
    BackendFillOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'fill is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> typeText(
    BackendCommandContext ctx,
    String text, [
    Map<String, Object?>? options,
  ]) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'typeText is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> focus(BackendCommandContext ctx, Point point) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'focus is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> longPress(
    BackendCommandContext ctx,
    Point point,
    BackendLongPressOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'longPress is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> swipe(
    BackendCommandContext ctx,
    Point from,
    Point to,
    BackendSwipeOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'swipe is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> scroll(
    BackendCommandContext ctx,
    BackendScrollTarget target,
    BackendScrollOptions options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'scroll is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> pinch(
    BackendCommandContext ctx,
    BackendPinchOptions options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'pinch is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> pressKey(
    BackendCommandContext ctx,
    String key, [
    Map<String, Object?>? options,
  ]) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'pressKey is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> pressBack(
    BackendCommandContext ctx,
    BackendBackOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'pressBack is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> pressHome(BackendCommandContext ctx) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'pressHome is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> rotate(
    BackendCommandContext ctx,
    BackendDeviceOrientation orientation,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'rotate is not supported on Android',
    );
  }

  @override
  Future<Object?> setKeyboard(
    BackendCommandContext ctx,
    BackendKeyboardOptions options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'setKeyboard is not supported on Android',
    );
  }

  @override
  Future<String> getClipboard(BackendCommandContext ctx) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'getClipboard is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> setClipboard(
    BackendCommandContext ctx,
    String text,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'setClipboard is not supported on Android',
    );
  }

  @override
  Future<BackendAlertResult> handleAlert(
    BackendCommandContext ctx,
    BackendAlertAction action, [
    Map<String, Object?>? options,
  ]) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'handleAlert is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> openSettings(
    BackendCommandContext ctx, [
    String? target,
  ]) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'openSettings is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> openAppSwitcher(BackendCommandContext ctx) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'openAppSwitcher is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> openApp(
    BackendCommandContext ctx,
    BackendOpenTarget target,
    BackendOpenOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'openApp is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> closeApp(
    BackendCommandContext ctx, [
    String? app,
  ]) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'closeApp is not supported on Android',
    );
  }

  @override
  Future<List<BackendAppInfo>> listApps(
    BackendCommandContext ctx, [
    BackendAppListFilter? filter,
  ]) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'listApps is not supported on Android',
    );
  }

  @override
  Future<BackendAppState> getAppState(BackendCommandContext ctx, String app) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'getAppState is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> pushFile(
    BackendCommandContext ctx,
    BackendPushInput input,
    String target,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'pushFile is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> triggerAppEvent(
    BackendCommandContext ctx,
    BackendAppEvent event,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'triggerAppEvent is not supported on Android',
    );
  }

  @override
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'listDevices is not supported on Android',
    );
  }

  @override
  Future<BackendActionResult> bootDevice(
    BackendCommandContext ctx, [
    BackendDeviceTarget? target,
  ]) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'bootDevice is not supported on Android',
    );
  }

  @override
  Future<BackendEnsureSimulatorResult> ensureSimulator(
    BackendCommandContext ctx,
    BackendEnsureSimulatorOptions options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'ensureSimulator is not supported on Android',
    );
  }

  @override
  Future<BackendInstallSource> resolveInstallSource(
    BackendCommandContext ctx,
    BackendInstallSource source,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'resolveInstallSource is not supported on Android',
    );
  }

  @override
  Future<BackendInstallResult> installApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'installApp is not supported on Android',
    );
  }

  @override
  Future<BackendInstallResult> reinstallApp(
    BackendCommandContext ctx,
    BackendInstallTarget target,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'reinstallApp is not supported on Android',
    );
  }

  @override
  Future<BackendRecordingResult> startRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'startRecording is not supported on Android',
    );
  }

  @override
  Future<BackendRecordingResult> stopRecording(
    BackendCommandContext ctx,
    BackendRecordingOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'stopRecording is not supported on Android',
    );
  }

  @override
  Future<BackendTraceResult> startTrace(
    BackendCommandContext ctx,
    BackendTraceOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'startTrace is not supported on Android',
    );
  }

  @override
  Future<BackendTraceResult> stopTrace(
    BackendCommandContext ctx,
    BackendTraceOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'stopTrace is not supported on Android',
    );
  }

  @override
  Future<BackendReadLogsResult> readLogs(
    BackendCommandContext ctx,
    BackendReadLogsOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'readLogs is not supported on Android',
    );
  }

  @override
  Future<BackendDumpNetworkResult> dumpNetwork(
    BackendCommandContext ctx,
    BackendDumpNetworkOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'dumpNetwork is not supported on Android',
    );
  }

  @override
  Future<BackendMeasurePerfResult> measurePerf(
    BackendCommandContext ctx,
    BackendMeasurePerfOptions? options,
  ) {
    throw AppError(
      AppErrorCodes.unsupportedOperation,
      'measurePerf is not supported on Android',
    );
  }
}
