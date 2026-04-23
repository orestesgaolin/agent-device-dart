import 'dart:io';

import 'package:agent_device/agent_device.dart';

Future<void> main(List<String> argv) async {
  if (argv.contains('--version') || argv.contains('-V')) {
    stdout.writeln(packageVersion);
    return;
  }
  stderr.writeln(
    'agent-device (Dart port, v$packageVersion): CLI not yet implemented. '
    'See PORTING_PLAN.md for roadmap.',
  );
  exitCode = 1;
}
