// Unit coverage for the xctrace activity-monitor-process-live XML parser.
// Fixture is the real output from a 1-second trace recorded against a
// paired iPhone 12 mini — 427 rows covering every system process.

import 'dart:io';

import 'package:agent_device/src/platforms/ios/perf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('parseIosDevicePerfXml', () {
    late String xml;

    setUpAll(() {
      final fixture = File(
        p.join(
          _findPackageRoot(),
          'test',
          'platforms',
          'ios',
          'fixtures',
          'xctrace_activity_monitor.xml',
        ),
      );
      xml = fixture.readAsStringSync();
    });

    test('parses every row from a real 1s activity-monitor capture', () {
      final samples = parseIosDevicePerfXml(xml);
      expect(
        samples.length,
        greaterThan(100),
        reason: 'A 1s all-processes trace should yield hundreds of rows.',
      );
      // Every sample must have a non-negative pid + non-empty process
      // name (kernel_task reports pid=0, so `>= 0` is the tight bound).
      for (final s in samples) {
        expect(s.pid, greaterThanOrEqualTo(0));
        expect(s.processName, isNotEmpty);
      }
    });

    test('extracts launchd (pid 1) with non-null memory', () {
      final samples = parseIosDevicePerfXml(xml);
      final launchd = samples.where((s) => s.pid == 1).toList();
      expect(
        launchd,
        isNotEmpty,
        reason: 'launchd at pid 1 should always be present on iOS.',
      );
      expect(launchd.first.processName, contains('launchd'));
      expect(launchd.first.residentMemoryBytes, greaterThan(0));
    });

    test('returns empty on malformed XML', () {
      expect(parseIosDevicePerfXml(''), isEmpty);
      expect(parseIosDevicePerfXml('<not-xctrace />'), isEmpty);
      expect(parseIosDevicePerfXml('not even xml'), isEmpty);
    });
  });

  group('computeIosDevicePerfDelta', () {
    final t1 = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final t2 = t1.add(const Duration(seconds: 2));

    test('CPU% = ΔcpuTime / wall * 100, summed across matched pids', () {
      // Same 2 pids in both snapshots. Pid 100 burned 0.5s of CPU over
      // 2s wall (= 25%). Pid 200 burned 1.0s (= 50%). Total = 75%.
      final first = [
        const IosDeviceProcessSample(
          pid: 100,
          processName: 'demo (100)',
          cpuTimeNs: 1_000_000_000,
          residentMemoryBytes: 100_000_000,
        ),
        const IosDeviceProcessSample(
          pid: 200,
          processName: 'demo (200)',
          cpuTimeNs: 2_000_000_000,
          residentMemoryBytes: 50_000_000,
        ),
      ];
      final second = [
        const IosDeviceProcessSample(
          pid: 100,
          processName: 'demo (100)',
          cpuTimeNs: 1_500_000_000,
          residentMemoryBytes: 110_000_000,
        ),
        const IosDeviceProcessSample(
          pid: 200,
          processName: 'demo (200)',
          cpuTimeNs: 3_000_000_000,
          residentMemoryBytes: 60_000_000,
        ),
      ];
      final r = computeIosDevicePerfDelta(
        firstSamples: first,
        secondSamples: second,
        firstCapturedAt: t1,
        secondCapturedAt: t2,
        processMatcher: (n) => n.startsWith('demo'),
        matcherLabel: 'demo',
      );
      expect(r.cpu.usagePercent, closeTo(75.0, 0.01));
      // Memory uses the second snapshot — 110+60 = 170 MB ≈ 166015 kB.
      expect(
        r.memory.residentMemoryKb,
        equals(((110_000_000 + 60_000_000) / 1024).round()),
      );
      expect(r.cpu.matchedProcesses, containsAll(['demo (100)', 'demo (200)']));
    });

    test('skips CPU contribution from pids without a baseline', () {
      // Pid 200 is new in the second snapshot — no baseline to diff
      // against, so it contributes 0 to CPU delta but full memory.
      final first = [
        const IosDeviceProcessSample(
          pid: 100,
          processName: 'demo (100)',
          cpuTimeNs: 1_000_000_000,
          residentMemoryBytes: 100_000_000,
        ),
      ];
      final second = [
        const IosDeviceProcessSample(
          pid: 100,
          processName: 'demo (100)',
          cpuTimeNs: 1_500_000_000,
          residentMemoryBytes: 110_000_000,
        ),
        const IosDeviceProcessSample(
          pid: 200,
          processName: 'demo (200)',
          cpuTimeNs: 999_000_000_000, // huge lifetime, but no prior
          residentMemoryBytes: 50_000_000,
        ),
      ];
      final r = computeIosDevicePerfDelta(
        firstSamples: first,
        secondSamples: second,
        firstCapturedAt: t1,
        secondCapturedAt: t2,
        processMatcher: (n) => n.startsWith('demo'),
        matcherLabel: 'demo',
      );
      expect(r.cpu.usagePercent, closeTo(25.0, 0.01));
    });

    test('throws COMMAND_FAILED when nothing matches the second snapshot', () {
      expect(
        () => computeIosDevicePerfDelta(
          firstSamples: const [],
          secondSamples: const [
            IosDeviceProcessSample(
              pid: 1,
              processName: 'launchd',
              cpuTimeNs: 1,
              residentMemoryBytes: 1,
            ),
          ],
          firstCapturedAt: t1,
          secondCapturedAt: t2,
          processMatcher: (_) => false,
          matcherLabel: 'demo',
        ),
        throwsA(isA<Object>()),
      );
    });

    test('throws when the wall window is zero/negative', () {
      expect(
        () => computeIosDevicePerfDelta(
          firstSamples: const [
            IosDeviceProcessSample(
              pid: 100,
              processName: 'demo (100)',
              cpuTimeNs: 0,
              residentMemoryBytes: 0,
            ),
          ],
          secondSamples: const [
            IosDeviceProcessSample(
              pid: 100,
              processName: 'demo (100)',
              cpuTimeNs: 0,
              residentMemoryBytes: 0,
            ),
          ],
          firstCapturedAt: t1,
          secondCapturedAt: t1, // same timestamp
          processMatcher: (n) => n.startsWith('demo'),
          matcherLabel: 'demo',
        ),
        throwsA(isA<Object>()),
      );
    });
  });
}

String _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 10; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir.path, 'test', 'platforms')).existsSync()) {
      return dir.path;
    }
    final nested = Directory(p.join(dir.path, 'packages', 'agent_device'));
    if (nested.existsSync() &&
        File(p.join(nested.path, 'pubspec.yaml')).existsSync()) {
      return nested.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
