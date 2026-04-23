/// Public API for the agent_device Dart port.
///
/// Mirrors the TypeScript `src/index.ts` export surface of the upstream
/// `agent-device` package. Individual symbols are added as their source
/// modules are ported (see PORTING_PLAN.md).
library;

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
export 'src/version.dart';
