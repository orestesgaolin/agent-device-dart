/// Public API for the agent_device Dart port.
///
/// Mirrors the TypeScript `src/index.ts` export surface of the upstream
/// `agent-device` package. Individual symbols are added as their source
/// modules are ported (see PORTING_PLAN.md).
library;

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
