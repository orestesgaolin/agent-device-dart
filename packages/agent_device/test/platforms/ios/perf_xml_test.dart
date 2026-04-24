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
          'packages',
          'agent_device',
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
}
