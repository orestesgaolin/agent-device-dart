// Port of agent-device/src/platforms/ios/runner-client.ts + runner-transport.ts
// + runner-session.ts (MVP slice).
//
// Minimum viable XCUITest-runner bridge for Phase 8B: prepare an
// `.xctestrun` file with a pre-picked port, launch the runner detached
// via `xcodebuild test-without-building`, wait for the `AGENT_DEVICE_RUNNER_PORT=`
// log line, then POST JSON commands at `http://127.0.0.1:<port>/command`.
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

/// Live connection to an XCUITest runner process on a simulator.
class IosRunnerSession {
  final String udid;
  final int port;
  final int xcodebuildPid;
  final String xctestrunPath;
  final String logPath;

  const IosRunnerSession({
    required this.udid,
    required this.port,
    required this.xcodebuildPid,
    required this.xctestrunPath,
    required this.logPath,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'udid': udid,
    'port': port,
    'xcodebuildPid': xcodebuildPid,
    'xctestrunPath': xctestrunPath,
    'logPath': logPath,
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
    );
  }
}

/// Launch + manage the XCUITest runner.
class IosRunnerClient {
  /// Resolve the base directory of the built iOS runner — where the
  /// `*.xctestrun` file and `Debug-iphonesimulator/` sit.
  ///
  /// Priority: `AGENT_DEVICE_IOS_RUNNER_BUILD_DIR` env var → repo-local
  /// `<repoRoot>/ios-runner/build/Build/Products/`.
  static String resolveBuildProductsDir({String? override}) {
    final env =
        override ?? Platform.environment['AGENT_DEVICE_IOS_RUNNER_BUILD_DIR'];
    if (env != null && env.trim().isNotEmpty) return env.trim();
    // Walk up from cwd until we find a sibling `ios-runner/` directory.
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
      final candidate = Directory(
        p.join(dir.path, 'ios-runner', 'build', 'Build', 'Products'),
      );
      if (candidate.existsSync()) return candidate.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    // Last resort: a conventional path relative to cwd. Will fail loudly
    // when [findXctestrun] can't find the file.
    return p.join(
      Directory.current.path,
      'ios-runner',
      'build',
      'Build',
      'Products',
    );
  }

  /// Find the `.xctestrun` template in [productsDir]. Throws if there
  /// isn't exactly one.
  static File findXctestrun(String productsDir) {
    final dir = Directory(productsDir);
    if (!dir.existsSync()) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'iOS runner has not been built — missing directory: $productsDir',
        details: {
          'hint':
              'Run `xcodebuild build-for-testing -project '
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
    if (files.length > 1) {
      // Prefer the iphonesimulator variant.
      final sim = files.firstWhere(
        (f) => f.path.contains('iphonesimulator'),
        orElse: () => files.first,
      );
      return sim;
    }
    return files.first;
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
  /// Throws `AppError` with `COMMAND_FAILED` if the runner doesn't come
  /// up within [startupTimeout].
  static Future<IosRunnerSession> launch({
    required String udid,
    String? buildProductsDirOverride,
    Duration startupTimeout = const Duration(seconds: 60),
  }) async {
    final productsDir = resolveBuildProductsDir(
      override: buildProductsDirOverride,
    );
    final template = findXctestrun(productsDir);
    final port = await pickFreePort();
    final xctestrunPath = await prepareXctestrunWithEnv(
      template: template,
      productsDir: productsDir,
      envVars: {'AGENT_DEVICE_RUNNER_PORT': '$port'},
    );

    final logDir = await Directory.systemTemp.createTemp('ad-ios-runner-log-');
    final logPath = p.join(logDir.path, 'runner.log');
    // xcodebuild writes to stdout; redirect via `sh -c '… > log 2>&1'`
    // so the detached subprocess has nowhere for the parent to drain.
    final proc = await runCmdDetached('sh', [
      '-c',
      'exec xcodebuild test-without-building '
          '-xctestrun ${_shq(xctestrunPath)} '
          '-destination "platform=iOS Simulator,id=$udid" '
          "-only-testing 'AgentDeviceRunnerUITests/RunnerTests/testCommand' "
          '-parallel-testing-enabled NO '
          '-test-timeouts-enabled NO '
          '> ${_shq(logPath)} 2>&1',
    ], const ExecDetachedOptions());

    // Poll the log for the readiness line OR hit the port directly.
    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      // Try the socket first — succeeds as soon as the listener is up.
      final ok = await _probePort(port);
      if (ok) {
        return IosRunnerSession(
          udid: udid,
          port: port,
          xcodebuildPid: proc.pid,
          xctestrunPath: xctestrunPath,
          logPath: logPath,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    // Timeout — capture the last few log lines so the error is useful.
    String tail = '';
    try {
      final file = File(logPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final text = utf8.decode(bytes, allowMalformed: true);
        final lines = text.split('\n');
        tail = lines
            .sublist(lines.length > 40 ? lines.length - 40 : 0)
            .join('\n');
      }
    } catch (_) {}
    // Kill the xcodebuild tree so we don't leak zombies.
    try {
      Process.killPid(proc.pid, ProcessSignal.sigkill);
    } catch (_) {}
    throw AppError(
      AppErrorCodes.commandFailed,
      'iOS runner did not become ready on port $port within '
      '${startupTimeout.inSeconds}s.',
      details: {
        'udid': udid,
        'port': port,
        'xctestrunPath': xctestrunPath,
        'logTail': tail,
      },
    );
  }

  /// POST a JSON [body] to `http://127.0.0.1:<session.port>/command`
  /// with the runner protocol envelope. Returns the parsed response.
  static Future<RunnerResponse> send(
    IosRunnerSession session,
    Map<String, Object?> body, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client
          .postUrl(Uri.parse('http://127.0.0.1:${session.port}/command'))
          .timeout(timeout);
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
  static Future<bool> isAlive(IosRunnerSession session) async =>
      _probePort(session.port);

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
