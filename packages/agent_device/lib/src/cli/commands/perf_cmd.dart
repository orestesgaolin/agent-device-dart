// `agent-device perf` — sample CPU and memory usage for the current app.
// iOS simulator uses `simctl spawn ps`; Android uses
// `adb shell dumpsys cpuinfo|meminfo`.
library;

import 'package:agent_device/src/backend/diagnostics.dart'
    show BackendMeasurePerfResult;
import 'package:agent_device/src/utils/errors.dart';

import '../base_command.dart';

class PerfCommand extends AgentDeviceCommand {
  PerfCommand() {
    argParser.addMultiOption(
      'metric',
      help:
          'Which metrics to sample. Repeat the flag to request multiple '
          '(e.g. --metric cpu --metric memory). Default: both.',
      allowed: const ['cpu', 'memory'],
    );
  }

  @override
  String get name => 'perf';

  @override
  String get description =>
      'Sample CPU and memory usage for the session\'s open app.';

  @override
  Future<int> run() async {
    final metrics = (argResults?['metric'] as List<String>? ?? const <String>[])
        .toSet()
        .toList();
    final device = await openAgentDevice();
    final BackendMeasurePerfResult res;
    try {
      res = await device.measurePerf(metrics: metrics.isEmpty ? null : metrics);
    } on AppError catch (e) {
      if (e.code == AppErrorCodes.invalidArgs) rethrow;
      rethrow;
    }
    emitResult(
      res.toJson(),
      humanFormat: (_) {
        if (res.metrics.isEmpty) return '(no metrics sampled)';
        final buf = StringBuffer();
        if (res.backend != null) buf.writeln('backend: ${res.backend}');
        for (final m in res.metrics) {
          buf.write('${m.name.padRight(18)} ');
          if (m.value != null) {
            final formatted = m.unit == 'percent'
                ? m.value!.toStringAsFixed(1)
                : m.value!.toInt().toString();
            buf.write('$formatted ${m.unit ?? ''}'.trimRight());
          }
          final procs = m.metadata?['matchedProcesses'];
          if (procs is List && procs.isNotEmpty) {
            buf.write('  (${procs.join(', ')})');
          }
          buf.writeln();
        }
        return buf.toString().trimRight();
      },
    );
    return 0;
  }
}
