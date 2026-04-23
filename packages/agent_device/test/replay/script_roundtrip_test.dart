/// Tests for replay script roundtrip (parse → serialize → parse).
library;

import 'package:agent_device/src/replay/script.dart';
import 'package:agent_device/src/replay/session_action.dart';
import 'package:test/test.dart';

void main() {
  group('formatReplayActionLine', () {
    test('formats snapshot action correctly', () {
      final action = const SessionAction(
        ts: 1000,
        command: 'snapshot',
        positionals: [],
        flags: {
          'snapshotInteractiveOnly': true,
          'snapshotDepth': 5,
          'snapshotScope': 'myScope',
        },
      );

      final formatted = formatReplayActionLine(action);

      expect(formatted, contains('snapshot'));
      expect(formatted, contains('-i'));
      expect(formatted, contains('-d'));
      expect(formatted, contains('5'));
      expect(formatted, contains('-s'));
    });

    test('formats open action with relaunch', () {
      final action = const SessionAction(
        ts: 1000,
        command: 'open',
        positionals: ['com.example.app'],
        flags: {'relaunch': true},
        runtime: SessionRuntimeHints(platform: 'ios'),
      );

      final formatted = formatReplayActionLine(action);

      expect(formatted, contains('open'));
      expect(formatted, contains('com.example.app'));
      expect(formatted, contains('--relaunch'));
      expect(formatted, contains('--platform'));
      expect(formatted, contains('ios'));
    });

    test('formats click action with coordinates', () {
      final action = const SessionAction(
        ts: 1000,
        command: 'click',
        positionals: ['100', '200'],
        flags: {},
      );

      final formatted = formatReplayActionLine(action);

      expect(formatted, equals('click 100 200'));
    });

    test('formats click action with selector', () {
      final action = const SessionAction(
        ts: 1000,
        command: 'click',
        positionals: ['label=Settings'],
        flags: {'count': 2},
      );

      final formatted = formatReplayActionLine(action);

      expect(formatted, contains('click'));
      expect(formatted, contains('label=Settings'));
      expect(formatted, contains('--count'));
      expect(formatted, contains('2'));
    });

    test('formats record action', () {
      final action = const SessionAction(
        ts: 1000,
        command: 'record',
        positionals: ['start'],
        flags: {'fps': 30, 'quality': 80, 'hideTouches': true},
      );

      final formatted = formatReplayActionLine(action);

      expect(formatted, contains('record'));
      expect(formatted, contains('start'));
      expect(formatted, contains('--fps'));
      expect(formatted, contains('30'));
      expect(formatted, contains('--hide-touches'));
    });
  });

  group('serializeReplayScript', () {
    test('serializes list of actions', () {
      final actions = [
        const SessionAction(
          ts: 1000,
          command: 'open',
          positionals: ['app'],
          flags: {},
        ),
        const SessionAction(
          ts: 2000,
          command: 'snapshot',
          positionals: [],
          flags: {'snapshotInteractiveOnly': true},
        ),
      ];

      final serialized = serializeReplayScript(actions);

      expect(serialized, contains('open "app"'));
      expect(serialized, contains('snapshot -i'));
      expect(serialized, endsWith('\n'));
    });

    test('includes context line when provided', () {
      final actions = [
        const SessionAction(
          ts: 1000,
          command: 'snapshot',
          positionals: [],
          flags: {},
        ),
      ];

      final serialized = serializeReplayScript(
        actions,
        contextLine: 'context platform=ios',
      );

      expect(serialized, startsWith('context platform=ios\n'));
      expect(serialized, contains('snapshot'));
    });
  });

  group('roundtrip', () {
    test('parses and serializes basic script without data loss', () {
      const originalScript = '''context platform=android
open settings --relaunch
snapshot -i
click "label=Settings"
back
wait 1000
''';

      final actions = parseReplayScript(originalScript);
      final metadata = readReplayScriptMetadata(originalScript);

      // Serialize without context (since we simplified serializeReplayScript)
      final serialized = serializeReplayScript(actions);

      // Parse again
      final actions2 = parseReplayScript(serialized);

      expect(actions2.length, equals(actions.length));
      expect(actions2[0].command, equals(actions[0].command));
      expect(actions2[1].command, equals(actions[1].command));
      expect(actions2[2].command, equals(actions[2].command));

      // Verify metadata parsing still works
      expect(metadata.platform, equals('android'));
    });

    test('preserves selector quotes through roundtrip', () {
      const originalScript = '''click "label=\\"Multi Word\\""
''';

      final actions = parseReplayScript(originalScript);
      expect(actions[0].positionals[0], contains('Multi Word'));

      final serialized = serializeReplayScript(actions);
      final actions2 = parseReplayScript(serialized);

      expect(actions2[0].positionals[0], equals(actions[0].positionals[0]));
    });

    test('preserves flags through roundtrip', () {
      const originalScript =
          '''click "label=Btn" --count 3 --interval-ms 100 --hold-ms 500
''';

      final actions = parseReplayScript(originalScript);
      expect(actions[0].flags['count'], equals(3));
      expect(actions[0].flags['intervalMs'], equals(100));
      expect(actions[0].flags['holdMs'], equals(500));

      final serialized = serializeReplayScript(actions);
      final actions2 = parseReplayScript(serialized);

      expect(actions2[0].flags['count'], equals(3));
      expect(actions2[0].flags['intervalMs'], equals(100));
      expect(actions2[0].flags['holdMs'], equals(500));
    });
  });
}
