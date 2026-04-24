// Port of agent-device/src/platforms/ios/runner-client.ts + runner-transport.ts
// + runner-session.ts.
//
// XCUITest-runner bridge. Prepares an `.xctestrun` file with a pre-picked
// port, launches the runner detached via `xcodebuild test-without-building`,
// waits for the HTTP listener, then POSTs JSON commands at the runner's
// command endpoint.
//
// Simulator: the runner's loopback port is reachable on the host at
// `127.0.0.1:<port>` directly because the sim shares the host network
// stack.
//
// Physical device: the runner listens inside the device; we reach it
// over the CoreDevice USB tunnel using the IPv6 address returned by
// `xcrun devicectl device info details`. On device we hit
// `http://[<tunnelIp>]:<port>/command` first and fall back to loopback
// (which shouldn't succeed — kept only so stale records don't hang
// forever on a port probe).
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/exec.dart';
import 'package:path/path.dart' as p;

/// JSON envelope returned by the runner: `{ok: bool, data|error: ...}`.
class RunnerResponse {
  final bool ok;
  final Object? data;
  final String? errorMessage;

  const RunnerResponse({required this.ok, this.data, this.errorMessage});
}

/// Device kind the runner is driving. Determines xctestrun variant,
/// xcodebuild destination, and how the host reaches the HTTP endpoint.
enum IosRunnerKind {
  simulator('simulator'),
  device('device');

  final String wire;
  const IosRunnerKind(this.wire);

  static IosRunnerKind parse(String? raw) =>
      raw == 'device' ? IosRunnerKind.device : IosRunnerKind.simulator;
}

/// Live connection to an XCUITest runner process.
class IosRunnerSession {
  final String udid;
  final int port;
  final int xcodebuildPid;
  final String xctestrunPath;
  final String logPath;
  final IosRunnerKind kind;

  /// IPv6 CoreDevice tunnel IP. Populated for [IosRunnerKind.device] on
  /// launch, null for simulators. Re-resolved on `send` if the cached
  /// value stops working.
  final String? tunnelIp;

  const IosRunnerSession({
    required this.udid,
    required this.port,
    required this.xcodebuildPid,
    required this.xctestrunPath,
    required this.logPath,
    this.kind = IosRunnerKind.simulator,
    this.tunnelIp,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'udid': udid,
    'port': port,
    'xcodebuildPid': xcodebuildPid,
    'xctestrunPath': xctestrunPath,
    'logPath': logPath,
    'kind': kind.wire,
    if (tunnelIp != null) 'tunnelIp': tunnelIp,
  };

  static IosRunnerSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final udid = raw['udid'];
    final port = raw['port'];
    final pid = raw['xcodebuildPid'];
    final xctr = raw['xctestrunPath'];
    final log = raw['logPath'];
    if (udid is! String ||
        port is! int ||
        pid is! int ||
        xctr is! String ||
        log is! String) {
      return null;
    }
    return IosRunnerSession(
      udid: udid,
      port: port,
      xcodebuildPid: pid,
      xctestrunPath: xctr,
      logPath: log,
      kind: IosRunnerKind.parse(raw['kind'] as String?),
      tunnelIp: raw['tunnelIp'] as String?,
    );
  }

  IosRunnerSession copyWith({String? tunnelIp}) => IosRunnerSession(
    udid: udid,
    port: port,
    xcodebuildPid: xcodebuildPid,
    xctestrunPath: xctestrunPath,
    logPath: logPath,
    kind: kind,
    tunnelIp: tunnelIp ?? this.tunnelIp,
  );
}

/// Launch + manage the XCUITest runner.
class IosRunnerClient {
  /// Resolve the base directory of the built iOS runner — where the
  /// `*.xctestrun` file + `Debug-iphoneos/` or `Debug-iphonesimulator/`
  /// sit.
  ///
  /// Priority: explicit [override] arg → `AGENT_DEVICE_IOS_RUNNER_BUILD_DIR`
  /// env var → walk up for a sibling `ios-runner/` and pick the kind-
  /// appropriate sub-path (`build-device/…` for device, `build/…` for
  /// simulator).
  static String resolveBuildProductsDir({
    String? override,
    IosRunnerKind kind = IosRunnerKind.simulator,
  }) {
    final env =
        override ?? Platform.environment['AGENT_DEVICE_IOS_RUNNER_BUILD_DIR'];
    if (env != null && env.trim().isNotEmpty) return env.trim();
    final buildSubdir = kind == IosRunnerKind.device ? 'build-device' : 'build';
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
      final candidate = Directory(
        p.join(dir.path, 'ios-runner', buildSubdir, 'Build', 'Products'),
      );
      if (candidate.existsSync()) return candidate.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return p.join(
      Directory.current.path,
      'ios-runner',
      buildSubdir,
      'Build',
      'Products',
    );
  }

  /// Find the `.xctestrun` template in [productsDir]. Throws if there
  /// isn't a matching file. Picks the `iphoneos` variant for device,
  /// `iphonesimulator` for sim.
  static File findXctestrun(
    String productsDir, {
    IosRunnerKind kind = IosRunnerKind.simulator,
  }) {
    final dir = Directory(productsDir);
    if (!dir.existsSync()) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'iOS runner has not been built — missing directory: $productsDir',
        details: {
          'hint': kind == IosRunnerKind.device
              ? 'Run `xcodebuild build-for-testing -project '
                    'ios-runner/AgentDeviceRunner/AgentDeviceRunner.xcodeproj '
                    '-scheme AgentDeviceRunner -destination "generic/platform=iOS" '
                    '-derivedDataPath ios-runner/build-device` once with a '
                    'provisioning profile that covers the target device.'
              : 'Run `xcodebuild build-for-testing -project '
                    'ios-runner/AgentDeviceRunner/AgentDeviceRunner.xcodeproj '
                    '-scheme AgentDeviceRunner -destination "generic/platform=iOS Simulator" '
                    '-derivedDataPath ios-runner/build` once.',
        },
      );
    }
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.xctestrun'))
        .toList();
    if (files.isEmpty) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'No .xctestrun file found in $productsDir — runner is not built.',
      );
    }
    final wanted = kind == IosRunnerKind.device
        ? 'iphoneos'
        : 'iphonesimulator';
    final matching = files.firstWhere(
      (f) => f.path.contains(wanted),
      orElse: () => files.first,
    );
    return matching;
  }

  /// Prepare a patched copy of [template] under `/tmp/` with the
  /// `__TESTROOT__` placeholder resolved to [productsDir] and the given
  /// [envVars] merged into the test target's `EnvironmentVariables`.
  /// Returns the path to the patched file.
  static Future<String> prepareXctestrunWithEnv({
    required File template,
    required String productsDir,
    required Map<String, String> envVars,
  }) async {
    final tmpDir = await Directory.systemTemp.createTemp('ad-ios-runner-');
    final out = File(p.join(tmpDir.path, 'runner.xctestrun'));
    await out.writeAsBytes(await template.readAsBytes());

    // Convert to XML, substitute __TESTROOT__ (plutil can't rewrite
    // string values — only add/remove keys), convert back to binary.
    await runCmd('plutil', ['-convert', 'xml1', out.path]);
    final xml = await out.readAsString();
    final patched = xml.replaceAll('__TESTROOT__', productsDir);
    await out.writeAsString(patched);
    await runCmd('plutil', ['-convert', 'binary1', out.path]);

    for (final entry in envVars.entries) {
      await runCmd('plutil', [
        '-insert',
        'TestConfigurations.0.TestTargets.0.EnvironmentVariables.${entry.key}',
        '-string',
        entry.value,
        out.path,
      ]);
    }
    return out.path;
  }

  /// Pick a free ephemeral TCP port on loopback by binding briefly.
  static Future<int> pickFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// Launch the runner against [udid] and wait for its HTTP listener to
  /// accept requests. Uses a detached `xcodebuild test-without-building`
  /// so the runner can outlive the CLI process when the caller wants to
  /// cache it on the session.
  ///
  /// [kind] selects simulator vs physical-device mode — drives the
  /// xctestrun choice, the xcodebuild `-destination` string, and the
  /// HTTP endpoint resolution after launch (tunnel IP for device,
  /// loopback for sim).
  ///
  /// Throws `AppError` with `COMMAND_FAILED` if the runner doesn't come
  /// up within [startupTimeout].
  static Future<IosRunnerSession> launch({
    required String udid,
    IosRunnerKind kind = IosRunnerKind.simulator,
    String? buildProductsDirOverride,
    Duration? startupTimeout,
  }) async {
    // Device first-launch is much slower than simulator (code-signing
    // validation + CoreDevice handshake + app launch over USB). Default
    // to a generous budget when the caller doesn't override.
    startupTimeout ??= kind == IosRunnerKind.device
        ? const Duration(seconds: 180)
        : const Duration(seconds: 60);
    final productsDir = resolveBuildProductsDir(
      override: buildProductsDirOverride,
      kind: kind,
    );
    final template = findXctestrun(productsDir, kind: kind);
    final port = await pickFreePort();
    final xctestrunPath = await prepareXctestrunWithEnv(
      template: template,
      productsDir: productsDir,
      envVars: {'AGENT_DEVICE_RUNNER_PORT': '$port'},
    );

    final logDir = await Directory.systemTemp.createTemp('ad-ios-runner-log-');
    final logPath = p.join(logDir.path, 'runner.log');
    final destination = kind == IosRunnerKind.device
        ? 'platform=iOS,id=$udid'
        : 'platform=iOS Simulator,id=$udid';
    // xcodebuild writes to stdout; redirect via `sh -c '… > log 2>&1'`
    // so the detached subprocess has nowhere for the parent to drain.
    final proc = await runCmdDetached('sh', [
      '-c',
      'exec xcodebuild test-without-building '
          '-xctestrun ${_shq(xctestrunPath)} '
          '-destination ${_shq(destination)} '
          "-only-testing 'AgentDeviceRunnerUITests/RunnerTests/testCommand' "
          '-parallel-testing-enabled NO '
          '-test-timeouts-enabled NO '
          '> ${_shq(logPath)} 2>&1',
    ], const ExecDetachedOptions());

    // Resolve the tunnel IP in the background while we probe. Only
    // needed on device; null for simulator.
    final tunnelIpFuture = kind == IosRunnerKind.device
        ? resolveDeviceTunnelIp(udid, timeoutMs: 8000)
        : Future<String?>.value(null);

    // Poll until the HTTP listener is up. For simulator we probe
    // loopback TCP; for device we try the tunnel IP (once resolved)
    // and do an HTTP GET/POST since raw TCP connect against the IPv6
    // tunnel can get stuck on some systems.
    final deadline = DateTime.now().add(startupTimeout);
    String? tunnelIp;
    while (DateTime.now().isBefore(deadline)) {
      if (kind == IosRunnerKind.simulator) {
        if (await _probePort(port)) {
          return IosRunnerSession(
            udid: udid,
            port: port,
            xcodebuildPid: proc.pid,
            xctestrunPath: xctestrunPath,
            logPath: logPath,
            kind: kind,
          );
        }
      } else {
        tunnelIp ??= await tunnelIpFuture;
        if (tunnelIp != null) {
          if (await _probeRunnerEndpoint(
            _commandUrl(tunnelIp, port),
            timeout: const Duration(seconds: 2),
          )) {
            return IosRunnerSession(
              udid: udid,
              port: port,
              xcodebuildPid: proc.pid,
              xctestrunPath: xctestrunPath,
              logPath: logPath,
              kind: kind,
              tunnelIp: tunnelIp,
            );
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    // Timeout — capture log text (full for diagnosis, tail for display).
    String fullLog = '';
    String tail = '';
    try {
      final file = File(logPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        fullLog = utf8.decode(bytes, allowMalformed: true);
        final lines = fullLog.split('\n');
        tail = lines
            .sublist(lines.length > 40 ? lines.length - 40 : 0)
            .join('\n');
      }
    } catch (_) {}
    try {
      Process.killPid(proc.pid, ProcessSignal.sigkill);
    } catch (_) {}
    // XCUITest device-side config errors are recurring support pain
    // points (Developer Mode, cert-trust, device lock) — try to
    // recognize them and surface an actionable hint rather than a
    // generic timeout. Scan the WHOLE log (patterns often appear
    // mid-run, not just at the tail).
    final hint = _diagnoseRunnerStartupFailure(fullLog, kind);
    throw AppError(
      AppErrorCodes.commandFailed,
      'iOS runner did not become ready on port $port within '
      '${startupTimeout.inSeconds}s.',
      details: {
        'udid': udid,
        'kind': kind.wire,
        'port': port,
        'tunnelIp': tunnelIp,
        'xctestrunPath': xctestrunPath,
        'logTail': tail,
        if (hint != null) 'hint': hint,
      },
    );
  }

  /// Scan the xcodebuild log tail for common XCUITest failure patterns
  /// and return a human-readable hint the user can act on. Returns null
  /// if nothing matched — fall back to the generic timeout message.
  static String? _diagnoseRunnerStartupFailure(
    String logTail,
    IosRunnerKind kind,
  ) {
    if (logTail.contains('Timed out while enabling automation mode')) {
      return kind == IosRunnerKind.device
          ? 'The UI test runner failed to enable automation mode on the '
                'device. On physical iOS this usually means: (1) Developer '
                'Mode is not enabled — toggle it at `Settings > Privacy & '
                'Security > Developer Mode`, then reboot the device. (2) The '
                'runner app signature is not trusted — launch '
                '`AgentDeviceRunner` once manually from the home screen and '
                'approve the developer at `Settings > General > VPN & Device '
                'Management`. (3) The device is locked — unlock it before '
                'retrying.'
          : 'UI test failed to enable automation mode. Close all Xcode '
                'windows running a test against this simulator, boot the '
                'simulator fresh, and retry.';
    }
    if (logTail.contains('UITesting') &&
        logTail.contains('failed to install')) {
      return 'The runner app failed to install on the device. Check that '
          'the provisioning profile covers this UDID and that the device '
          'is paired + trusted in Xcode > Devices.';
    }
    if (logTail.contains('Could not launch') && logTail.contains('signature')) {
      return 'The runner\'s code signature was rejected by the device. '
          'Re-build with `xcodebuild build-for-testing -destination '
          '"generic/platform=iOS" -derivedDataPath ios-runner/build-device` '
          'using a provisioning profile that covers this device.';
    }
    // Catch-all: the runner got as far as launching the test bundle
    // ("Running tests...") but never emitted AGENT_DEVICE_RUNNER_PORT.
    // On device this is usually an automation-mode or trust issue.
    if (kind == IosRunnerKind.device &&
        logTail.contains('Running tests...') &&
        !logTail.contains('AGENT_DEVICE_RUNNER_PORT=')) {
      return 'The XCUITest runner launched but never opened its HTTP '
          'listener. On physical iOS this typically means automation mode '
          'couldn\'t be enabled. Check: (1) `Settings > Privacy & Security > '
          'Developer Mode` is ON and the device has been rebooted since. '
          '(2) The `AgentDeviceRunner` target app (dev.roszkowski.'
          'agentdevice.runner) is installed + trusted — launch it once '
          'manually from the home screen and approve the developer at '
          '`Settings > General > VPN & Device Management`. (3) Device is '
          'unlocked during the run.';
    }
    return null;
  }

  /// Pull the CoreDevice tunnel IPv6 address for [udid]. Returns null on
  /// any error (device asleep, not trusted, etc.) — callers fall back
  /// to the deadline.
  static Future<String?> resolveDeviceTunnelIp(
    String udid, {
    int timeoutMs = 8000,
  }) async {
    final tmp = File(
      p.join(
        Directory.systemTemp.path,
        'ad-devicectl-info-$pid-${DateTime.now().microsecondsSinceEpoch}.json',
      ),
    );
    try {
      final r = await runCmd('xcrun', [
        'devicectl',
        'device',
        'info',
        'details',
        '--device',
        udid,
        '--json-output',
        tmp.path,
        '--timeout',
        '${(timeoutMs / 1000).ceil()}',
      ], ExecOptions(allowFailure: true, timeoutMs: timeoutMs));
      if (r.exitCode != 0 || !await tmp.exists()) return null;
      final raw = jsonDecode(await tmp.readAsString());
      if (raw is! Map) return null;
      final info = raw['info'];
      if (info is Map &&
          info['outcome'] != null &&
          info['outcome'] != 'success') {
        return null;
      }
      final result = raw['result'];
      if (result is! Map) return null;
      final direct =
          (result['connectionProperties'] as Map?)?['tunnelIPAddress']
              as String?;
      if (direct != null && direct.trim().isNotEmpty) return direct.trim();
      final nested =
          (((result['device'] as Map?)?['connectionProperties']
                  as Map?)?['tunnelIPAddress'])
              as String?;
      if (nested != null && nested.trim().isNotEmpty) return nested.trim();
      return null;
    } on FormatException {
      return null;
    } finally {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }

  /// Build the HTTP command URL for [session]. IPv6 tunnel for device,
  /// loopback for simulator.
  static String _commandUrl(String host, int port) {
    final authority = host.contains(':') ? '[$host]' : host;
    return 'http://$authority:$port/command';
  }

  /// Probe an HTTP endpoint with a short connect timeout. Returns true
  /// iff we received any HTTP response (even an error — that still
  /// proves the listener is up). Every awaitable step is bounded so a
  /// half-open connection can never block the launch poller.
  static Future<bool> _probeRunnerEndpoint(
    String url, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.postUrl(Uri.parse(url)).timeout(timeout);
      req.headers.set('Content-Type', 'application/json');
      req.add(utf8.encode('{}'));
      final res = await req.close().timeout(timeout);
      await res.drain<void>().timeout(timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// POST a JSON [body] to the runner's command endpoint. For simulator
  /// sessions that's `http://127.0.0.1:<port>/command`; for device it's
  /// `http://[<tunnelIp>]:<port>/command`.
  ///
  /// Uses the single cached endpoint — no per-send tunnel re-resolve,
  /// no fallback chain. If the cached tunnel IP ever goes stale the
  /// caller should explicitly reset the session; silently retrying
  /// against stale addresses with 30-second timeouts just hangs the
  /// user's terminal.
  static Future<RunnerResponse> send(
    IosRunnerSession session,
    Map<String, Object?> body, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final url = _sessionEndpoint(session);
    return _postCommand(url, body, timeout: timeout);
  }

  static String _sessionEndpoint(IosRunnerSession s) {
    if (s.kind == IosRunnerKind.simulator) {
      return _commandUrl('127.0.0.1', s.port);
    }
    final host = s.tunnelIp ?? '127.0.0.1';
    return _commandUrl(host, s.port);
  }

  static Future<RunnerResponse> _postCommand(
    String url,
    Map<String, Object?> body, {
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(Uri.parse(url)).timeout(timeout);
      req.headers.set('Content-Type', 'application/json');
      final encoded = utf8.encode(jsonEncode(body));
      req.contentLength = encoded.length;
      req.add(encoded);
      final res = await req.close().timeout(timeout);
      final bytes = await res
          .fold<List<int>>(<int>[], (a, b) {
            a.addAll(b);
            return a;
          })
          .timeout(timeout);
      final text = utf8.decode(bytes);
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw AppError(
          AppErrorCodes.commandFailed,
          'iOS runner returned a non-object response: $text',
        );
      }
      final ok = decoded['ok'] == true;
      if (!ok) {
        final err = decoded['error'];
        final message = err is Map && err['message'] is String
            ? err['message'] as String
            : 'iOS runner reported failure: $text';
        return RunnerResponse(ok: false, errorMessage: message);
      }
      return RunnerResponse(ok: true, data: decoded['data']);
    } finally {
      client.close(force: true);
    }
  }

  /// Best-effort graceful shutdown. Sends `{command: 'shutdown'}`,
  /// waits briefly, then SIGKILLs the xcodebuild parent if it's still up.
  static Future<void> stop(IosRunnerSession session) async {
    try {
      await send(session, const {
        'command': 'shutdown',
      }, timeout: const Duration(seconds: 3));
    } catch (_) {
      // Expected if the runner is already wedged.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      Process.killPid(session.xcodebuildPid, ProcessSignal.sigkill);
    } catch (_) {}
  }

  /// Check whether [session] is still reachable. Used by session-scoped
  /// caching to decide whether to reuse a prior runner.
  static Future<bool> isAlive(IosRunnerSession session) async {
    if (session.kind == IosRunnerKind.simulator) {
      return _probePort(session.port);
    }
    // Device: try the cached tunnel IP via HTTP (IPv6 connects over the
    // tunnel can hang on raw TCP without the HTTP framing).
    if (session.tunnelIp == null) return false;
    return _probeRunnerEndpoint(
      _commandUrl(session.tunnelIp!, session.port),
      timeout: const Duration(seconds: 2),
    );
  }

  static Future<bool> _probePort(int port) async {
    try {
      final s = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _shq(String s) => "'${s.replaceAll("'", r"'\''")}'";
}
