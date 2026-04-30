// Unit tests for the iOS frame perf parsing logic.
// Port of the parseAppleFramePerfSample tests from
// agent-device/src/platforms/ios/__tests__/perf.test.ts.

import 'package:agent_device/src/platforms/ios/perf_frame.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// XML fixture builders (mirroring the TS test helpers)
// ---------------------------------------------------------------------------

String _makeAppleHitchesXml() {
  return [
    '<?xml version="1.0"?>',
    '<trace-query-result><node>',
    '<schema name="hitches">',
    '<col><mnemonic>start</mnemonic></col>',
    '<col><mnemonic>duration</mnemonic></col>',
    '<col><mnemonic>process</mnemonic></col>',
    '<col><mnemonic>is-system</mnemonic></col>',
    '<col><mnemonic>swap-id</mnemonic></col>',
    '<col><mnemonic>label</mnemonic></col>',
    '<col><mnemonic>display</mnemonic></col>',
    '<col><mnemonic>narrative-description</mnemonic></col>',
    '</schema>',
    // Row 1: app hitch, pid 4001, 16.67ms duration.
    '<row>',
    '<start-time id="start-1" fmt="00:00.100">100000000</start-time>',
    '<duration id="duration-1" fmt="16.67 ms">16666583</duration>',
    '<process id="process-1" fmt="ExampleDeviceApp (4001)">'
        '<pid id="pid-1" fmt="4001">4001</pid></process>',
    '<boolean id="false" fmt="No">0</boolean>',
    '<uint32>1</uint32><string>0x1</string>'
        '<display-name>Display 1</display-name><string></string>',
    '</row>',
    // Row 2: same process via ref, 37.5ms duration.
    '<row>',
    '<start-time fmt="00:00.200">200000000</start-time>',
    '<duration fmt="37.50 ms">37500000</duration>',
    '<process ref="process-1"/>',
    '<boolean ref="false"/>',
    '<uint32>2</uint32><string>0x2</string>'
        '<display-name>Display 1</display-name><string></string>',
    '</row>',
    // Row 3: system hitch (is-system == 1) — should be filtered out.
    '<row>',
    '<start-time fmt="00:00.200">200000000</start-time>',
    '<duration ref="duration-1"/>',
    '<sentinel/>',
    '<boolean fmt="Yes">1</boolean>',
    '<uint32>2</uint32><string>0x2</string>'
        '<display-name>Display 1</display-name><string></string>',
    '</row>',
    // Row 4: different process (pid 5001) — should be filtered by caller.
    '<row>',
    '<start-time fmt="00:00.300">300000000</start-time>',
    '<duration fmt="16.67 ms">16666583</duration>',
    '<process fmt="OtherApp (5001)"><pid fmt="5001">5001</pid></process>',
    '<boolean ref="false"/>',
    '<uint32>3</uint32><string>0x3</string>'
        '<display-name>Display 1</display-name><string></string>',
    '</row>',
    '</node></trace-query-result>',
  ].join('');
}

String _makeAppleFrameLifetimesXml(int count) {
  final rows = List<String>.generate(
    count,
    (i) =>
        '<row><start-time>${i * 16000000}</start-time>'
        '<duration>16000000</duration></row>',
  );
  return [
    '<?xml version="1.0"?>',
    '<trace-query-result><node>',
    '<schema name="hitches-frame-lifetimes">',
    '<col><mnemonic>start</mnemonic></col>',
    '<col><mnemonic>duration</mnemonic></col>',
    '</schema>',
    ...rows,
    '</node></trace-query-result>',
  ].join('');
}

String _makeAppleDisplayInfoXml(int refreshRateHz) {
  return [
    '<?xml version="1.0"?>',
    '<trace-query-result><node>',
    '<schema name="device-display-info">',
    '<col><mnemonic>timestamp</mnemonic></col>',
    '<col><mnemonic>accelerator-id</mnemonic></col>',
    '<col><mnemonic>display-id</mnemonic></col>',
    '<col><mnemonic>device-name</mnemonic></col>',
    '<col><mnemonic>framebuffer-index</mnemonic></col>',
    '<col><mnemonic>resolution</mnemonic></col>',
    '<col><mnemonic>built-in</mnemonic></col>',
    '<col><mnemonic>max-refresh-rate</mnemonic></col>',
    '<col><mnemonic>is-main-display</mnemonic></col>',
    '</schema>',
    '<row>'
        '<event-time>0</event-time>'
        '<uint64>1</uint64>'
        '<uint64>1</uint64>'
        '<string>Display</string>'
        '<uint32>0</uint32>'
        '<string>390 844</string>'
        '<boolean>1</boolean>'
        '<uint32>$refreshRateHz</uint32>'
        '<boolean>1</boolean>'
        '</row>',
    '</node></trace-query-result>',
  ].join('');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('parseAppleFramePerfSample', () {
    test('summarizes app hitches and worst windows', () {
      final sample = parseAppleFramePerfSample(
        hitchesXml: _makeAppleHitchesXml(),
        frameLifetimesXml: _makeAppleFrameLifetimesXml(4),
        displayInfoXml: _makeAppleDisplayInfoXml(120),
        processIds: [4001],
        processNames: ['ExampleDeviceApp'],
        windowStartedAt: '2026-04-01T10:00:00.000Z',
        windowEndedAt: '2026-04-01T10:00:02.000Z',
        measuredAt: '2026-04-01T10:00:02.000Z',
      );

      expect(sample.droppedFrameCount, equals(2));
      expect(sample.totalFrameCount, equals(4));
      expect(sample.droppedFramePercent, equals(50.0));
      expect(sample.sampleWindowMs, equals(2000));
      expect(sample.refreshRateHz, equals(120.0));
      expect(sample.frameDeadlineMs, closeTo(8.3, 0.01));
      expect(sample.matchedProcesses, equals(['ExampleDeviceApp']));
      expect(sample.method, equals('xctrace-animation-hitches'));

      final windows = sample.worstWindows;
      expect(windows, isNotNull);
      expect(windows!, hasLength(1));
      expect(windows[0].startOffsetMs, equals(100));
      expect(windows[0].endOffsetMs, equals(238));
      expect(windows[0].startAt, equals('2026-04-01T10:00:00.100Z'));
      expect(windows[0].endAt, equals('2026-04-01T10:00:00.238Z'));
      expect(windows[0].missedDeadlineFrameCount, equals(2));
      expect(windows[0].worstFrameMs, closeTo(37.5, 0.01));
    });

    test('returns zero percent when no frames were recorded', () {
      final sample = parseAppleFramePerfSample(
        hitchesXml: _makeAppleHitchesXml(),
        frameLifetimesXml: _makeAppleFrameLifetimesXml(0),
        processIds: [4001],
        processNames: [],
        windowStartedAt: '2026-04-01T10:00:00.000Z',
        windowEndedAt: '2026-04-01T10:00:02.000Z',
        measuredAt: '2026-04-01T10:00:02.000Z',
      );

      expect(sample.droppedFramePercent, equals(0.0));
      expect(sample.totalFrameCount, equals(0));
    });

    test('excludes system hitches from the count', () {
      // The XML has 3 non-sentinel rows for pid 4001 (rows 1 & 2) plus a
      // system row (row 3). Only 2 should be counted.
      final sample = parseAppleFramePerfSample(
        hitchesXml: _makeAppleHitchesXml(),
        frameLifetimesXml: _makeAppleFrameLifetimesXml(4),
        processIds: [4001],
        processNames: [],
        windowStartedAt: '2026-04-01T10:00:00.000Z',
        windowEndedAt: '2026-04-01T10:00:02.000Z',
        measuredAt: '2026-04-01T10:00:02.000Z',
      );
      expect(sample.droppedFrameCount, equals(2));
    });

    test('filters hitches by process name when pid does not match', () {
      final sample = parseAppleFramePerfSample(
        hitchesXml: _makeAppleHitchesXml(),
        frameLifetimesXml: _makeAppleFrameLifetimesXml(4),
        processIds: [],
        processNames: ['ExampleDeviceApp'],
        windowStartedAt: '2026-04-01T10:00:00.000Z',
        windowEndedAt: '2026-04-01T10:00:02.000Z',
        measuredAt: '2026-04-01T10:00:02.000Z',
      );
      expect(sample.droppedFrameCount, equals(2));
    });

    test('omits display info fields when displayInfoXml is absent', () {
      final sample = parseAppleFramePerfSample(
        hitchesXml: _makeAppleHitchesXml(),
        frameLifetimesXml: _makeAppleFrameLifetimesXml(4),
        processIds: [4001],
        processNames: [],
        windowStartedAt: '2026-04-01T10:00:00.000Z',
        windowEndedAt: '2026-04-01T10:00:02.000Z',
        measuredAt: '2026-04-01T10:00:02.000Z',
      );
      expect(sample.refreshRateHz, isNull);
      expect(sample.frameDeadlineMs, isNull);
    });

    test('worstWindows is null when no hitches match', () {
      final sample = parseAppleFramePerfSample(
        hitchesXml: _makeAppleHitchesXml(),
        frameLifetimesXml: _makeAppleFrameLifetimesXml(10),
        // No matching process.
        processIds: [9999],
        processNames: [],
        windowStartedAt: '2026-04-01T10:00:00.000Z',
        windowEndedAt: '2026-04-01T10:00:02.000Z',
        measuredAt: '2026-04-01T10:00:02.000Z',
      );
      expect(sample.droppedFrameCount, equals(0));
      expect(sample.worstWindows, isNull);
    });

    test('caps worst windows at 3', () {
      // Build XML with 4 well-separated hitches for pid 4001 so each forms
      // its own jank window.
      final rows = StringBuffer();
      // Start times spaced > 500ms apart so each forms its own window.
      final starts = [
        100000000,
        700000000,
        1300000000,
        1900000000,
      ];
      for (var i = 0; i < starts.length; i++) {
        rows.write('<row>');
        rows.write(
          '<start-time fmt="x">${starts[i]}</start-time>',
        );
        rows.write('<duration fmt="x">37500000</duration>');
        rows.write(
          '<process fmt="App (4001)"><pid fmt="4001">4001</pid></process>',
        );
        rows.write('<boolean fmt="No">0</boolean>');
        rows.write('<uint32>$i</uint32><string>x</string>'
            '<display-name>D</display-name><string></string>');
        rows.write('</row>');
      }
      final xml = [
        '<?xml version="1.0"?>',
        '<trace-query-result><node>',
        '<schema name="hitches">',
        '<col><mnemonic>start</mnemonic></col>',
        '<col><mnemonic>duration</mnemonic></col>',
        '<col><mnemonic>process</mnemonic></col>',
        '<col><mnemonic>is-system</mnemonic></col>',
        '<col><mnemonic>swap-id</mnemonic></col>',
        '<col><mnemonic>label</mnemonic></col>',
        '<col><mnemonic>display</mnemonic></col>',
        '<col><mnemonic>narrative-description</mnemonic></col>',
        '</schema>',
        rows.toString(),
        '</node></trace-query-result>',
      ].join('');

      final sample = parseAppleFramePerfSample(
        hitchesXml: xml,
        frameLifetimesXml: _makeAppleFrameLifetimesXml(100),
        processIds: [4001],
        processNames: [],
        windowStartedAt: '2026-04-01T10:00:00.000Z',
        windowEndedAt: '2026-04-01T10:00:02.000Z',
        measuredAt: '2026-04-01T10:00:02.000Z',
      );

      expect(sample.worstWindows, isNotNull);
      expect(sample.worstWindows!, hasLength(3));
    });

    test('returns empty sample on malformed hitches XML', () {
      final sample = parseAppleFramePerfSample(
        hitchesXml: 'not valid xml',
        frameLifetimesXml: _makeAppleFrameLifetimesXml(10),
        processIds: [4001],
        processNames: [],
        windowStartedAt: '2026-04-01T10:00:00.000Z',
        windowEndedAt: '2026-04-01T10:00:02.000Z',
        measuredAt: '2026-04-01T10:00:02.000Z',
      );
      expect(sample.droppedFrameCount, equals(0));
      expect(sample.droppedFramePercent, equals(0.0));
    });

    test('sampleWindowMs is derived from window timestamps', () {
      final sample = parseAppleFramePerfSample(
        hitchesXml: _makeAppleHitchesXml(),
        frameLifetimesXml: _makeAppleFrameLifetimesXml(4),
        processIds: [4001],
        processNames: [],
        windowStartedAt: '2026-04-01T10:00:00.000Z',
        windowEndedAt: '2026-04-01T10:00:03.500Z',
        measuredAt: '2026-04-01T10:00:03.500Z',
      );
      expect(sample.sampleWindowMs, equals(3500));
    });
  });
}
