import 'dart:io';

import 'package:agent_device/agent_device.dart';
import 'package:agent_device/src/cli/run_cli.dart';

Future<void> main(List<String> argv) async {
  if (argv.contains('--version') || argv.contains('-V')) {
    stdout.writeln(packageVersion);
    return;
  }
  final code = await runCli(argv);
  // Explicit exit: on iOS paths we leave the XCUITest runner detached so
  // subsequent invocations can reuse it, but the Dart VM can still be
  // kept alive for tens of seconds by HttpClient keepalive timers or
  // other lingering resources. Force exit so the user never pays that
  // idle-wait at the terminal.
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
