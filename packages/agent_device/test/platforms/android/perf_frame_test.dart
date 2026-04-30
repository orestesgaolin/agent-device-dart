// Port of agent-device/src/platforms/android/__tests__/perf.test.ts
// (frame perf cases only — CPU/memory cases live in perf_test.dart)

import 'package:agent_device/src/platforms/android/perf_frame_analysis.dart';
import 'package:agent_device/src/platforms/android/perf_frame_parser.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // parseAndroidFramePerfSample — framestats rows only
  // ---------------------------------------------------------------------------
  group('parseAndroidFramePerfSample (framestats rows)', () {
    test('summarizes dropped frame percentage from framestats rows', () {
      final sample = parseAndroidFramePerfSample(
        [
          'Stats since: 123456789ns',
          '---PROFILEDATA---',
          'Flags,IntendedVsync,Vsync,OldestInputEvent,NewestInputEvent,'
              'HandleInputStart,AnimationStart,PerformTraversalsStart,DrawStart,'
              'SyncQueued,SyncStart,IssueDrawCommandsStart,SwapBuffers,'
              'FrameCompleted,DequeueBufferDuration,QueueBufferDuration,GpuCompleted',
          '0,1000000000,1000000000,0,0,0,0,0,0,0,0,0,0,1010000000,0,0,1010000000',
          '0,1016666667,1016666667,0,0,0,0,0,0,0,0,0,0,1034666667,0,0,1034666667',
          '0,1033333334,1033333334,0,0,0,0,0,0,0,0,0,0,1063333334,0,0,1063333334',
          '1,1050000001,1050000001,0,0,0,0,0,0,0,0,0,0,1100000001,0,0,1100000001',
          '0,1066666668,1066666668,0,0,0,0,0,0,0,0,0,0,1082666668,0,0,1082666668',
          '---PROFILEDATA---',
        ].join('\n'),
        'com.example.app',
        '2026-04-01T10:00:00.000Z',
      );

      expect(sample.droppedFrameCount, 2);
      expect(sample.totalFrameCount, 4);
      expect(sample.droppedFramePercent, 50);
      expect(sample.frameDeadlineMs, 16.7);
      expect(sample.refreshRateHz, 60);
      expect(sample.method, 'adb-shell-dumpsys-gfxinfo-framestats');
      expect(sample.source, 'framestats-rows');
      expect(sample.worstWindows, isNotNull);
      expect(sample.worstWindows!.first.missedDeadlineFrameCount, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // parseAndroidFramePerfSample — Android gfxinfo summary present
  // ---------------------------------------------------------------------------
  group('parseAndroidFramePerfSample (summary-based)', () {
    test('prefers Android gfxinfo janky frame summary', () {
      final sample = parseAndroidFramePerfSample(
        [
          'Applications Graphics Acceleration Info:',
          'Uptime: 164892458 Realtime: 164892458',
          '',
          '** Graphics info for pid 16305 [host.exp.exponent] **',
          '',
          'Stats since: 164496032562094ns',
          'Total frames rendered: 4569',
          'Janky frames: 115 (2.52%)',
          'Janky frames (legacy): 3971 (86.91%)',
          'Number Frame deadline missed: 115',
          'Profile data in ms:',
          'Flags,IntendedVsync,FrameCompleted',
          '0,1000000000,1010000000',
        ].join('\n'),
        'host.exp.exponent',
        '2026-04-01T10:00:00.000Z',
      );

      expect(sample.droppedFrameCount, 115);
      expect(sample.totalFrameCount, 4569);
      expect(sample.droppedFramePercent, 2.5);
      expect(sample.source, 'android-gfxinfo-summary');
    });

    test('omits frame deadline when rows are too sparse', () {
      final sample = parseAndroidFramePerfSample(
        [
          'Applications Graphics Acceleration Info:',
          'Uptime: 11000 Realtime: 11000',
          'Stats since: 10000000000ns',
          'Total frames rendered: 3',
          'Janky frames: 1 (33.33%)',
          'Profile data in ms:',
          'Flags,IntendedVsync,FrameCompleted',
          '0,10000000000,10012000000',
          '0,10150000000,10162000000',
          '0,10300000000,10312000000',
        ].join('\n'),
        'com.example.app',
        '2026-04-01T10:00:11.000Z',
      );

      expect(sample.droppedFramePercent, 33.3);
      expect(sample.frameDeadlineMs, isNull);
      expect(sample.refreshRateHz, isNull);
      expect(sample.worstWindows, isNotNull);
      expect(sample.worstWindows!.first.missedDeadlineFrameCount, 1);
    });

    test('caps worst windows to Android summary count', () {
      final sample = parseAndroidFramePerfSample(
        [
          'Applications Graphics Acceleration Info:',
          'Uptime: 11000 Realtime: 11000',
          'Stats since: 10000000000ns',
          'Total frames rendered: 5',
          'Janky frames: 1 (20.00%)',
          'Profile data in ms:',
          'Flags,IntendedVsync,Vsync,OldestInputEvent,NewestInputEvent,'
              'HandleInputStart,AnimationStart,PerformTraversalsStart,DrawStart,'
              'SyncQueued,SyncStart,IssueDrawCommandsStart,SwapBuffers,'
              'FrameCompleted,DequeueBufferDuration,QueueBufferDuration,GpuCompleted',
          '0,10000000000,10000000000,0,0,0,0,0,0,0,0,0,0,10018000000,0,0,10018000000',
          '0,10016666667,10016666667,0,0,0,0,0,0,0,0,0,0,10036666667,0,0,10036666667',
          '0,10033333334,10033333334,0,0,0,0,0,0,0,0,0,0,10063333334,0,0,10063333334',
        ].join('\n'),
        'com.example.app',
        '2026-04-01T10:00:11.000Z',
      );

      expect(sample.droppedFrameCount, 1);
      expect(sample.worstWindows, isNotNull);
      expect(sample.worstWindows!.first.missedDeadlineFrameCount, 1);
      expect(sample.worstWindows!.first.worstFrameMs, 30);
    });

    test('adds estimated timestamps and worst drop windows', () {
      final sample = parseAndroidFramePerfSample(
        [
          'Applications Graphics Acceleration Info:',
          'Uptime: 11000 Realtime: 11000',
          '',
          'Stats since: 10000000000ns',
          'Total frames rendered: 5',
          'Janky frames: 2 (40.00%)',
          'Profile data in ms:',
          'Flags,IntendedVsync,Vsync,OldestInputEvent,NewestInputEvent,'
              'HandleInputStart,AnimationStart,PerformTraversalsStart,DrawStart,'
              'SyncQueued,SyncStart,IssueDrawCommandsStart,SwapBuffers,'
              'FrameCompleted,DequeueBufferDuration,QueueBufferDuration,GpuCompleted',
          '0,10000000000,10000000000,0,0,0,0,0,0,0,0,0,0,10010000000,0,0,10010000000',
          '0,10016666667,10016666667,0,0,0,0,0,0,0,0,0,0,10076666667,0,0,10076666667',
          '0,10033333334,10033333334,0,0,0,0,0,0,0,0,0,0,10043333334,0,0,10043333334',
          '0,10050000001,10050000001,0,0,0,0,0,0,0,0,0,0,10120000001,0,0,10120000001',
          '0,10066666668,10066666668,0,0,0,0,0,0,0,0,0,0,10076666668,0,0,10076666668',
        ].join('\n'),
        'com.example.app',
        '2026-04-01T10:00:11.000Z',
      );

      expect(sample.windowStartedAt, '2026-04-01T10:00:10.000Z');
      expect(sample.windowEndedAt, '2026-04-01T10:00:11.000Z');
      expect(sample.timestampSource, 'estimated-from-device-uptime');
      expect(sample.worstWindows, isNotNull);
      expect(sample.worstWindows!.length, 1);
      expect(sample.worstWindows!.first.startOffsetMs, 17);
      expect(sample.worstWindows!.first.endOffsetMs, 120);
      expect(sample.worstWindows!.first.missedDeadlineFrameCount, 2);
      expect(sample.worstWindows!.first.worstFrameMs, 70);
    });

    test('treats a reset idle window as an available zero-frame sample', () {
      final sample = parseAndroidFramePerfSample(
        [
          'Applications Graphics Acceleration Info:',
          'Uptime: 165130629 Realtime: 165130629',
          'Stats since: 165111622765012ns',
          'Total frames rendered: 0',
          'Janky frames: 0 (0.00%)',
          'Number Frame deadline missed: 0',
        ].join('\n'),
        'host.exp.exponent',
        '2026-04-01T10:00:00.000Z',
      );

      expect(sample.droppedFrameCount, 0);
      expect(sample.totalFrameCount, 0);
      expect(sample.droppedFramePercent, 0);
      expect(sample.source, 'android-gfxinfo-summary');
    });
  });

  // ---------------------------------------------------------------------------
  // parseAndroidFramePerfSample — error cases
  // ---------------------------------------------------------------------------
  group('parseAndroidFramePerfSample (errors)', () {
    test('throws when process is not found', () {
      expect(
        () => parseAndroidFramePerfSample(
          'Error: no process found for: com.example.missing',
          'com.example.missing',
          '2026-04-01T10:00:00.000Z',
        ),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.commandFailed)
              .having(
                (e) => e.message,
                'message',
                contains('did not find a running process'),
              ),
        ),
      );
    });

    test('throws when output has no parseable content', () {
      expect(
        () => parseAndroidFramePerfSample(
          'Some unrelated output',
          'com.example.app',
          '2026-04-01T10:00:00.000Z',
        ),
        throwsA(isA<AppError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // deriveFrameDeadlineNs
  // ---------------------------------------------------------------------------
  group('deriveFrameDeadlineNs', () {
    test('returns null for empty frame list', () {
      expect(deriveFrameDeadlineNs([]), isNull);
    });

    test('returns null for single frame (no deltas)', () {
      expect(
        deriveFrameDeadlineNs([
          const AndroidFrameStatsRow(
            intendedVsyncNs: 1000000000,
            frameCompletedNs: 1010000000,
            durationNs: 10000000,
          ),
        ]),
        isNull,
      );
    });

    test('computes median delta for 60 Hz frames', () {
      // Consecutive vsyncs at ~16.67 ms (16666667 ns)
      final frames = [
        const AndroidFrameStatsRow(
          intendedVsyncNs: 1000000000,
          frameCompletedNs: 1010000000,
          durationNs: 10000000,
        ),
        const AndroidFrameStatsRow(
          intendedVsyncNs: 1016666667,
          frameCompletedNs: 1026000000,
          durationNs: 9333333,
        ),
        const AndroidFrameStatsRow(
          intendedVsyncNs: 1033333334,
          frameCompletedNs: 1043000000,
          durationNs: 9666666,
        ),
      ];
      final deadline = deriveFrameDeadlineNs(frames);
      expect(deadline, isNotNull);
      // Median of two deltas: 16666667 and 16666667 = 16666667
      expect(deadline, closeTo(16666667, 5));
    });

    test('ignores deltas outside the valid display range', () {
      // One very small delta (<4ms) and one very large delta (>50ms) — both filtered.
      final frames = [
        const AndroidFrameStatsRow(
          intendedVsyncNs: 1000000000,
          frameCompletedNs: 1010000000,
          durationNs: 10000000,
        ),
        const AndroidFrameStatsRow(
          intendedVsyncNs: 1001000000, // only 1ms gap — too small
          frameCompletedNs: 1011000000,
          durationNs: 10000000,
        ),
        const AndroidFrameStatsRow(
          intendedVsyncNs: 1200000000, // 199ms gap — too large
          frameCompletedNs: 1210000000,
          durationNs: 10000000,
        ),
      ];
      expect(deriveFrameDeadlineNs(frames), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // selectDroppedFrameRows
  // ---------------------------------------------------------------------------
  group('selectDroppedFrameRows', () {
    final frames = [
      const AndroidFrameStatsRow(
        intendedVsyncNs: 1000000000,
        frameCompletedNs: 1020000000, // 20ms duration
        durationNs: 20000000,
      ),
      const AndroidFrameStatsRow(
        intendedVsyncNs: 1016666667,
        frameCompletedNs: 1026000000, // ~9.3ms duration
        durationNs: 9333333,
      ),
      const AndroidFrameStatsRow(
        intendedVsyncNs: 1033333334,
        frameCompletedNs: 1060000000, // ~26.7ms duration
        durationNs: 26666666,
      ),
    ];

    test('filters by frameDeadlineNs when no summary count provided', () {
      // 16.67ms deadline in ns = 16666667
      final dropped = selectDroppedFrameRows(
        frames: frames,
        frameDeadlineNs: 16666667,
      );
      expect(dropped.length, 2); // 20ms and ~26.7ms frames
    });

    test('returns empty list when frameDeadlineNs is null and no summary', () {
      final dropped = selectDroppedFrameRows(frames: frames);
      expect(dropped, isEmpty);
    });

    test('returns empty list when summaryDroppedFrameCount is 0', () {
      final dropped = selectDroppedFrameRows(
        frames: frames,
        summaryDroppedFrameCount: 0,
      );
      expect(dropped, isEmpty);
    });

    test('selects slowest N rows when summaryDroppedFrameCount is set', () {
      final dropped = selectDroppedFrameRows(
        frames: frames,
        summaryDroppedFrameCount: 1,
      );
      // Slowest 1 row is the ~26.7ms frame
      expect(dropped.length, 1);
      expect(dropped.first.durationNs, 26666666);
    });
  });

  // ---------------------------------------------------------------------------
  // buildWorstFrameDropWindows
  // ---------------------------------------------------------------------------
  group('buildWorstFrameDropWindows', () {
    test('returns empty list when frames is empty', () {
      expect(
        buildWorstFrameDropWindows(
          frames: [],
          windowStartNs: 1000000000,
          measuredAtMs: 1000,
        ),
        isEmpty,
      );
    });

    test('returns empty list when windowStartNs is null', () {
      expect(
        buildWorstFrameDropWindows(
          frames: [
            const AndroidFrameStatsRow(
              intendedVsyncNs: 1000000000,
              frameCompletedNs: 1020000000,
              durationNs: 20000000,
            ),
          ],
          measuredAtMs: 1000,
        ),
        isEmpty,
      );
    });

    test('groups consecutive frames into a single window', () {
      final frames = [
        const AndroidFrameStatsRow(
          intendedVsyncNs: 1000000000,
          frameCompletedNs: 1020000000,
          durationNs: 20000000,
        ),
        const AndroidFrameStatsRow(
          intendedVsyncNs: 1020000001, // only 1ns gap — same window
          frameCompletedNs: 1050000000,
          durationNs: 29999999,
        ),
      ];
      final windows = buildWorstFrameDropWindows(
        frames: frames,
        windowStartNs: 1000000000,
        measuredAtMs: 1200,
      );
      expect(windows.length, 1);
      expect(windows.first.missedDeadlineFrameCount, 2);
      expect(windows.first.worstFrameMs, 30); // ~30ms
    });

    test('splits frames separated by more than 500ms into separate windows', () {
      final frames = [
        const AndroidFrameStatsRow(
          intendedVsyncNs: 1000000000,
          frameCompletedNs: 1020000000,
          durationNs: 20000000,
        ),
        // Gap: 1020000000 → 1600000001 = 580ms > 500ms threshold
        const AndroidFrameStatsRow(
          intendedVsyncNs: 1600000001,
          frameCompletedNs: 1630000000,
          durationNs: 29999999,
        ),
      ];
      final windows = buildWorstFrameDropWindows(
        frames: frames,
        windowStartNs: 1000000000,
        measuredAtMs: 2000,
      );
      expect(windows.length, 2);
    });

    test('caps result at 3 worst windows', () {
      // Build 4 isolated jank windows
      final frames = <AndroidFrameStatsRow>[];
      for (int i = 0; i < 4; i++) {
        final base = 1000000000 + i * 600000000; // 600ms gaps — separate windows
        frames.add(
          AndroidFrameStatsRow(
            intendedVsyncNs: base,
            frameCompletedNs: base + 20000000,
            durationNs: 20000000,
          ),
        );
      }
      final windows = buildWorstFrameDropWindows(
        frames: frames,
        windowStartNs: 1000000000,
        measuredAtMs: 5000,
      );
      expect(windows.length, 3);
    });

    test('includes wall-clock timestamps when uptimeMs is provided', () {
      // measuredAtMs=11000, uptimeMs=11000 → boot at epoch 0
      // frame at ns 10000000000 = 10000ms = epoch 10000
      final frames = [
        const AndroidFrameStatsRow(
          intendedVsyncNs: 10000000000,
          frameCompletedNs: 10020000000,
          durationNs: 20000000,
        ),
      ];
      final windows = buildWorstFrameDropWindows(
        frames: frames,
        windowStartNs: 10000000000,
        measuredAtMs: 11000,
        uptimeMs: 11000,
      );
      expect(windows.first.startAt, isNotNull);
      expect(windows.first.endAt, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // roundOneDecimal
  // ---------------------------------------------------------------------------
  group('roundOneDecimal', () {
    test('rounds to one decimal place', () {
      expect(roundOneDecimal(16.666666), closeTo(16.7, 0.001));
      expect(roundOneDecimal(60.0), 60);
      expect(roundOneDecimal(1000000000 / 16666667), closeTo(60, 0.5));
    });
  });
}
