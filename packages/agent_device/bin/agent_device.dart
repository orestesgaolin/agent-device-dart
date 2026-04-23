import 'dart:io';

import 'package:agent_device/agent_device.dart';
import 'package:agent_device/src/cli/run_cli.dart';

Future<void> main(List<String> argv) async {
  if (argv.contains('--version') || argv.contains('-V')) {
    stdout.writeln(packageVersion);
    return;
  }
  exitCode = await runCli(argv);
}
