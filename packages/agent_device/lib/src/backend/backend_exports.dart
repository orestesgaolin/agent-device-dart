// Port of agent-device/src/backend.ts
//
// Barrel re-export of all backend types for internal use.
library;

export 'backend.dart'
    show
        Backend,
        BackendActionResult,
        BackendCommandContext,
        BackendEscapeHatches,
        hasBackendCapability,
        hasBackendEscapeHatch;
export 'capabilities.dart' show BackendCapabilityName, BackendCapabilitySet;
export 'device_info.dart'
    show
        BackendAppEvent,
        BackendAppInfo,
        BackendAppListFilter,
        BackendAppState,
        BackendDeviceFilter,
        BackendDeviceInfo,
        BackendDeviceOrientation,
        BackendDeviceTarget;
export 'diagnostics.dart'
    show
        BackendDiagnosticsTimeWindow,
        BackendDumpNetworkOptions,
        BackendDumpNetworkResult,
        BackendLogEntry,
        BackendMeasurePerfOptions,
        BackendMeasurePerfResult,
        BackendNetworkEntry,
        BackendNetworkIncludeMode,
        BackendPerfMetric,
        BackendLogStreamOptions,
        BackendLogStreamResult,
        BackendReadLogsOptions,
        BackendReadLogsResult;
export 'install_source.dart'
    show
        BackendEnsureSimulatorOptions,
        BackendEnsureSimulatorResult,
        BackendInstallResult,
        BackendInstallTarget;
export 'options.dart'
    show
        BackendAlertAction,
        BackendAlertHandledResult,
        BackendAlertInfo,
        BackendAlertResult,
        BackendAlertStatusResult,
        BackendAlertWaitResult,
        BackendBackOptions,
        BackendClipboardTextResult,
        BackendFillOptions,
        BackendFindTextResult,
        BackendInstallSource,
        BackendInstallSourcePath,
        BackendInstallSourceUploadedArtifact,
        BackendInstallSourceUrl,
        BackendKeyboardOptions,
        BackendKeyboardResult,
        BackendLongPressOptions,
        BackendOpenOptions,
        BackendOpenTarget,
        BackendPinchOptions,
        BackendPushInput,
        BackendPushInputFile,
        BackendPushInputJson,
        BackendReadTextResult,
        BackendRecordingOptions,
        BackendRecordingResult,
        BackendRunnerCommand,
        BackendScreenshotOptions,
        BackendScreenshotResult,
        BackendScrollOptions,
        BackendScrollTarget,
        BackendScrollTargetPoint,
        BackendScrollTargetViewport,
        BackendShellResult,
        BackendSnapshotAnalysis,
        BackendSnapshotFreshness,
        BackendSnapshotOptions,
        BackendSnapshotResult,
        BackendSwipeOptions,
        BackendTapOptions,
        BackendTraceOptions,
        BackendTraceResult;
export 'platform.dart' show AgentDeviceBackendPlatform;
