/// Public API for the agent_device Dart port.
///
/// Mirrors the TypeScript `src/index.ts` export surface of the upstream
/// `agent-device` package. Individual symbols are added as their source
/// modules are ported (see PORTING_PLAN.md).
library;

// Backend interface and types
export 'src/backend/backend.dart'
    show
        Backend,
        BackendActionResult,
        BackendCommandContext,
        BackendEscapeHatches,
        hasBackendCapability,
        hasBackendEscapeHatch;
export 'src/backend/capabilities.dart'
    show BackendCapabilityName, BackendCapabilitySet;
export 'src/backend/device_info.dart'
    show
        BackendAppEvent,
        BackendAppInfo,
        BackendAppListFilter,
        BackendAppState,
        BackendDeviceFilter,
        BackendDeviceInfo,
        BackendDeviceOrientation,
        BackendDeviceTarget;
export 'src/backend/diagnostics.dart'
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
        BackendReadLogsOptions,
        BackendReadLogsResult;
export 'src/backend/install_source.dart'
    show
        BackendEnsureSimulatorOptions,
        BackendEnsureSimulatorResult,
        BackendInstallResult,
        BackendInstallTarget;
export 'src/backend/options.dart'
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
export 'src/backend/platform.dart' show AgentDeviceBackendPlatform;
export 'src/platforms/android/android_backend.dart' show AndroidBackend;
export 'src/platforms/platform_selector.dart'
    show
        PlatformSelector,
        isApplePlatform,
        parsePlatformSelector,
        platformSelectorToString;
export 'src/replay/open_script.dart'
    show appendOpenActionScriptArgs, parseReplayOpenFlags;
export 'src/replay/script.dart'
    show
        ReplayScriptMetadata,
        formatReplayActionLine,
        parseReplayScript,
        readReplayScriptMetadata,
        serializeReplayScript;
export 'src/replay/script_utils.dart'
    show
        formatScriptActionSummary,
        formatScriptArg,
        formatScriptArgQuoteIfNeeded,
        formatScriptStringLiteral,
        isClickLikeCommand;
export 'src/replay/session_action.dart' show SessionAction, SessionRuntimeHints;
// Runtime façade (programmatic API).
export 'src/runtime/agent_device.dart' show AgentDevice, DeviceSelector;
export 'src/runtime/contract.dart'
    show
        CommandClock,
        CommandPolicy,
        CommandSessionRecord,
        CommandSessionStore,
        DiagnosticsSink,
        SystemClock,
        localCommandPolicy,
        restrictedCommandPolicy;
export 'src/runtime/session_store.dart'
    show MemorySessionStore, createMemorySessionStore;
export 'src/selectors/selectors.dart'
    show
        IsPredicateResult,
        IsPredicate,
        Selector,
        SelectorChain,
        SelectorDiagnostics,
        SelectorResolution,
        SelectorTerm,
        buildSelectorChainForNode,
        evaluateIsPredicate,
        findSelectorChainMatch,
        formatSelectorFailure,
        isSelectorToken,
        isSupportedPredicate,
        isNodeEditable,
        isNodeVisible,
        matchesSelector,
        parseSelectorChain,
        resolveSelectorChain,
        splitIsSelectorArgs,
        splitSelectorFromArgs,
        tryParseSelectorChain;
export 'src/snapshot/snapshot.dart'
    show
        Point,
        Rect,
        ScreenshotOverlayRef,
        SnapshotNode,
        SnapshotVisibility,
        SnapshotVisibilityReason,
        centerOfRect;
export 'src/utils/diagnostics.dart'
    show
        DiagnosticEvent,
        DiagnosticLevel,
        DiagnosticsMetadata,
        DiagnosticsScopeOptions,
        EmitDiagnosticOptions,
        createRequestId,
        emitDiagnostic,
        flushDiagnosticsToSessionFile,
        getDiagnosticsMeta,
        withDiagnosticTimer,
        withDiagnosticsScope;
export 'src/utils/errors.dart'
    show
        AppError,
        AppErrorCodes,
        NormalizedError,
        asAppError,
        defaultHintForCode,
        isAgentDeviceError,
        normalizeAgentDeviceError,
        normalizeError,
        toAppErrorCode;
export 'src/utils/exec.dart'
    show
        ExecBackgroundResult,
        ExecDetachedOptions,
        ExecOptions,
        ExecStreamOptions,
        RunCmdResult,
        resolveExecutableOverridePath,
        resolveFileOverridePath,
        runCmd,
        runCmdBackground,
        runCmdDetached,
        runCmdStreaming,
        runCmdSync,
        whichCmd;
export 'src/utils/path_resolution.dart'
    show
        EnvMap,
        PathResolutionOptions,
        expandUserHomePath,
        resolveHomeDirectory,
        resolveUserPath;
export 'src/utils/png.dart' show decodePng, resizePngFileToMaxSize;
export 'src/utils/retry.dart'
    show
        CancelToken,
        Deadline,
        RetryAttemptContext,
        RetryOptions,
        RetryPolicy,
        RetryTelemetryEvent,
        TimeoutProfile,
        isEnvTruthy,
        retryWithPolicy,
        timeoutProfiles,
        withRetry;
export 'src/utils/timeouts.dart'
    show resolveTimeoutMs, resolveTimeoutSeconds, sleep;
export 'src/version.dart';
