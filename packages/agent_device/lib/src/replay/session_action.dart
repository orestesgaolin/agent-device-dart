/// Port of `agent-device/src/daemon/types.ts` — SessionAction and related types.
library;

/// Runtime hints passed to commands (platform, metro config, launch URL, etc.).
/// These shape how sessions are initialized.
class SessionRuntimeHints {
  final String? platform;
  final String? metroHost;
  final int? metroPort;
  final String? bundleUrl;
  final String? launchUrl;

  const SessionRuntimeHints({
    this.platform,
    this.metroHost,
    this.metroPort,
    this.bundleUrl,
    this.launchUrl,
  });

  /// Shallow copy with optional field overrides.
  SessionRuntimeHints copyWith({
    String? platform,
    String? metroHost,
    int? metroPort,
    String? bundleUrl,
    String? launchUrl,
  }) => SessionRuntimeHints(
    platform: platform ?? this.platform,
    metroHost: metroHost ?? this.metroHost,
    metroPort: metroPort ?? this.metroPort,
    bundleUrl: bundleUrl ?? this.bundleUrl,
    launchUrl: launchUrl ?? this.launchUrl,
  );

  /// JSON serialization.
  Map<String, Object?> toJson() => {
    if (platform != null) 'platform': platform,
    if (metroHost != null) 'metroHost': metroHost,
    if (metroPort != null) 'metroPort': metroPort,
    if (bundleUrl != null) 'bundleUrl': bundleUrl,
    if (launchUrl != null) 'launchUrl': launchUrl,
  };
}

/// A single action within a replay script: a command with positional args,
/// flags, and metadata. Mirrors TypeScript's `SessionAction`.
class SessionAction {
  /// Timestamp when the action was recorded or executed.
  final int ts;

  /// Command name (e.g., 'open', 'snapshot', 'click', 'type', etc.).
  final String command;

  /// Positional arguments to the command.
  final List<String> positionals;

  /// Named flags and their values; see snapshot-specific, series-specific, etc.
  final Map<String, Object?> flags;

  /// Optional runtime hints (platform, metro config, etc.) passed to session init.
  final SessionRuntimeHints? runtime;

  /// Optional result metadata (e.g., refLabel for resolved selectors).
  final Map<String, Object?>? result;

  const SessionAction({
    required this.ts,
    required this.command,
    required this.positionals,
    required this.flags,
    this.runtime,
    this.result,
  });

  /// Shallow copy with optional field overrides.
  SessionAction copyWith({
    int? ts,
    String? command,
    List<String>? positionals,
    Map<String, Object?>? flags,
    SessionRuntimeHints? runtime,
    Map<String, Object?>? result,
  }) => SessionAction(
    ts: ts ?? this.ts,
    command: command ?? this.command,
    positionals: positionals ?? this.positionals,
    flags: flags ?? this.flags,
    runtime: runtime ?? this.runtime,
    result: result ?? this.result,
  );

  /// JSON serialization (for debugging / testing).
  Map<String, Object?> toJson() => {
    'ts': ts,
    'command': command,
    'positionals': positionals,
    'flags': flags,
    if (runtime != null) 'runtime': runtime!.toJson(),
    if (result != null) 'result': result,
  };

  @override
  String toString() => 'SessionAction($command)';
}
