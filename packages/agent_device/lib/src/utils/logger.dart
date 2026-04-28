/// Unified logger for the agent_device package.
///
/// Backed by `package:cli_util/cli_logging.dart`. Use [logger] for all
/// diagnostic output:
///
/// - `logger.stdout(msg)` for info-level messages (always visible).
/// - `logger.trace(msg)` for debug/verbose messages (visible only when
///   verbose mode is active).
/// - `logger.progress(msg)` for long-running operations (shows a spinner
///   that completes with timing).
///
/// Call [initLogger] once at startup to select verbose vs standard mode.
library;

import 'package:cli_util/cli_logging.dart';

Logger _logger = Logger.standard();

/// The package-wide logger instance.
Logger get logger => _logger;

/// Initialise the logger. Call once at startup.
///
/// When [verbose] is `true`, `Logger.verbose()` is used — trace-level
/// messages become visible. Otherwise `Logger.standard()` is used.
void initLogger({required bool verbose}) {
  _logger = verbose ? Logger.verbose() : Logger.standard();
}
