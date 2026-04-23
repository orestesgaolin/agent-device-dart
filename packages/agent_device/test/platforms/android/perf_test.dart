import 'package:agent_device/src/platforms/android/perf.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

const String sampleCpuInfoOutput = '''
  12% 1234/com.app.test:process1: foo
   8% 5678/com.app.test: foo
   3% 9999/other.app: foo
  ''';

const String sampleMemInfoOutput = '''
Total PSS by process:
  123456 B com.app.test

TOTAL PSS:  987654 kB
TOTAL RSS:  456789 kB
''';

const String sampleMemInfoNoProcess = '''
Error: no process found for: com.app.notinstalled
''';

void main() {
  group('parseAndroidCpuInfoSample', () {
    test('parses valid cpu info', () {
      final sample = parseAndroidCpuInfoSample(
        sampleCpuInfoOutput,
        'com.app.test',
        '2026-04-23T10:00:00Z',
      );
      expect(sample.usagePercent, 20.0); // 12% + 8%
      expect(sample.matchedProcesses.length, 2);
      expect(sample.matchedProcesses, contains('com.app.test'));
      expect(sample.matchedProcesses, contains('com.app.test:process1'));
      expect(sample.method, androidCpuSampleMethod);
    });

    test('rounds usage percent to tenth', () {
      const testOutput = '  12.456% 1234/com.app.test: foo';
      final sample = parseAndroidCpuInfoSample(
        testOutput,
        'com.app.test',
        '2026-04-23T10:00:00Z',
      );
      expect(sample.usagePercent, 12.5); // rounded
    });

    test('filters non-matching processes', () {
      const testOutput = '''
  10% 111/com.app.test: foo
   5% 222/com.other.app: foo
  ''';
      final sample = parseAndroidCpuInfoSample(
        testOutput,
        'com.app.test',
        '2026-04-23T10:00:00Z',
      );
      expect(sample.usagePercent, 10.0);
      expect(sample.matchedProcesses.length, 1);
    });

    test('handles empty output', () {
      final sample = parseAndroidCpuInfoSample(
        '',
        'com.app.test',
        '2026-04-23T10:00:00Z',
      );
      expect(sample.usagePercent, 0.0);
      expect(sample.matchedProcesses, isEmpty);
    });
  });

  group('parseAndroidMemInfoSample', () {
    test('parses valid meminfo', () {
      final sample = parseAndroidMemInfoSample(
        sampleMemInfoOutput,
        'com.app.test',
        '2026-04-23T10:00:00Z',
      );
      expect(sample.totalPssKb, 987654);
      expect(sample.totalRssKb, 456789);
      expect(sample.method, androidMemorySampleMethod);
    });

    test('throws when process not found', () {
      expect(
        () => parseAndroidMemInfoSample(
          sampleMemInfoNoProcess,
          'com.app.test',
          '2026-04-23T10:00:00Z',
        ),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.commandFailed)
              .having((e) => e.message, 'message', contains('did not find')),
        ),
      );
    });

    test('handles missing RSS', () {
      const output = 'TOTAL PSS:  123456 kB\n';
      final sample = parseAndroidMemInfoSample(
        output,
        'com.app.test',
        '2026-04-23T10:00:00Z',
      );
      expect(sample.totalPssKb, 123456);
      expect(sample.totalRssKb, isNull);
    });

    test('parses numbers with commas', () {
      const output = 'TOTAL PSS:  1,234,567 kB\n';
      final sample = parseAndroidMemInfoSample(
        output,
        'com.app.test',
        '2026-04-23T10:00:00Z',
      );
      expect(sample.totalPssKb, 1234567);
    });
  });

  group('AndroidCpuPerfSample', () {
    test('creates sample', () {
      const sample = AndroidCpuPerfSample(
        usagePercent: 12.5,
        measuredAt: '2026-04-23T10:00:00Z',
        method: androidCpuSampleMethod,
        matchedProcesses: ['com.app.test'],
      );
      expect(sample.usagePercent, 12.5);
      expect(sample.matchedProcesses, ['com.app.test']);
    });
  });

  group('AndroidMemoryPerfSample', () {
    test('creates sample', () {
      const sample = AndroidMemoryPerfSample(
        totalPssKb: 987654,
        totalRssKb: 456789,
        measuredAt: '2026-04-23T10:00:00Z',
        method: androidMemorySampleMethod,
      );
      expect(sample.totalPssKb, 987654);
      expect(sample.totalRssKb, 456789);
    });
  });
}
