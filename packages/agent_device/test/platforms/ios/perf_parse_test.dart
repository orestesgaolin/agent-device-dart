// Unit coverage for the iOS simulator `ps` output parser.

import 'package:agent_device/src/platforms/ios/perf.dart';
import 'package:test/test.dart';

void main() {
  group('parseApplePsOutput', () {
    test('parses pid / cpu / rss / command', () {
      const stdout = '''
  123  2.5  18432  /path/to/MyApp/MyApp
 456  0.0   1024  /usr/libexec/helper
''';
      final samples = parseApplePsOutput(stdout);
      expect(samples, hasLength(2));
      expect(samples[0].pid, 123);
      expect(samples[0].cpuPercent, 2.5);
      expect(samples[0].rssKb, 18432);
      expect(samples[0].command, '/path/to/MyApp/MyApp');
      expect(samples[1].pid, 456);
      expect(samples[1].rssKb, 1024);
    });

    test('skips blank / unparseable lines', () {
      const stdout = '''
random header line

 42 1.1 512 /Users/me/app
''';
      final samples = parseApplePsOutput(stdout);
      expect(samples, hasLength(1));
      expect(samples[0].pid, 42);
    });

    test('parses integer-only %cpu values', () {
      const stdout = '  7  1  256  /bin/sh';
      final samples = parseApplePsOutput(stdout);
      expect(samples, hasLength(1));
      expect(samples[0].cpuPercent, 1);
    });
  });

  group('matchesAppleExecutableProcess', () {
    test('matches on basename', () {
      expect(
        matchesAppleExecutableProcess('/path/to/MyApp.app/MyApp', 'MyApp'),
        isTrue,
      );
    });
    test('tolerates trailing args in command', () {
      expect(
        matchesAppleExecutableProcess(
          '/path/to/MyApp.app/MyApp --flag value',
          'MyApp',
        ),
        isTrue,
      );
    });
    test(
      'survives simulator paths that contain spaces (iOS 26.2.simruntime)',
      () {
        const cmd =
            '/Library/Developer/CoreSimulator/Volumes/iOS_23C54/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.2.simruntime/Contents/Resources/RuntimeRoot/Applications/MobileSafari.app/MobileSafari';
        expect(matchesAppleExecutableProcess(cmd, 'MobileSafari'), isTrue);
      },
    );
    test('does not match unrelated processes', () {
      expect(
        matchesAppleExecutableProcess('/usr/libexec/helper', 'MyApp'),
        isFalse,
      );
    });
    test('does not false-match a bare suffix inside an argv token', () {
      // `/Applications/Other/MyAppSidekick` should NOT match `MyApp` —
      // the executable name must be preceded by a path separator.
      expect(
        matchesAppleExecutableProcess(
          '/Applications/Other/MyAppSidekick',
          'MyApp',
        ),
        isFalse,
      );
    });
  });
}
