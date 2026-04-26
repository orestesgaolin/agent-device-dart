// Unit coverage for the JUnit-XML emitter that backs
// `agent-device test --report-junit`. Pure-function tests — no device
// required.

import 'package:agent_device/src/cli/commands/replay_cmd.dart';
import 'package:test/test.dart';

void main() {
  group('buildJUnitReport', () {
    test('serialises a passing run as an empty <testcase /> tag', () {
      final xml = buildJUnitReport([
        {
          'scriptName': 'login.ad',
          'scriptDurationMs': 1500,
          'ok': true,
        },
      ]);
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<testsuite name="agent-device" tests="1" '
          'failures="0" time="1.500">'));
      expect(xml, contains('<testcase name="login.ad" time="1.500" />'));
      expect(xml, contains('</testsuite>'));
    });

    test('serialises a failure with <failure type/message>', () {
      final xml = buildJUnitReport([
        {
          'scriptName': 'broken.ad',
          'scriptDurationMs': 800,
          'ok': false,
          'errorCode': 'COMMAND_FAILED',
          'errorMessage': 'tap target not found',
        },
      ]);
      expect(xml, contains('failures="1"'));
      expect(
        xml,
        contains('<failure type="COMMAND_FAILED" '
            'message="tap target not found"></failure>'),
      );
      expect(xml, contains('</testcase>'));
    });

    test('escapes XML metacharacters in name + message', () {
      final xml = buildJUnitReport([
        {
          'scriptName': 'a&b<c>.ad',
          'scriptDurationMs': 0,
          'ok': false,
          'errorCode': 'FAIL',
          'errorMessage': 'value="quoted" & broken',
        },
      ]);
      expect(xml, contains('name="a&amp;b&lt;c&gt;.ad"'));
      expect(xml, contains('message="value=&quot;quoted&quot; &amp; broken"'));
      expect(xml, isNot(contains('& broken')));
    });

    test('aggregates total time + failure count across results', () {
      final xml = buildJUnitReport([
        {'scriptName': 'a.ad', 'scriptDurationMs': 1000, 'ok': true},
        {
          'scriptName': 'b.ad',
          'scriptDurationMs': 500,
          'ok': false,
          'errorCode': 'TIMEOUT',
          'errorMessage': 'replay timed out after 1000ms',
        },
        {'scriptName': 'c.ad', 'scriptDurationMs': 250, 'ok': true},
      ]);
      expect(xml, contains('tests="3"'));
      expect(xml, contains('failures="1"'));
      expect(xml, contains('time="1.750"'));
    });

    test('falls back to scriptPath when scriptName is missing', () {
      final xml = buildJUnitReport([
        {
          'scriptPath': '/abs/path/to/foo.ad',
          'scriptDurationMs': 0,
          'ok': true,
        },
      ]);
      expect(xml, contains('name="/abs/path/to/foo.ad"'));
    });
  });
}
