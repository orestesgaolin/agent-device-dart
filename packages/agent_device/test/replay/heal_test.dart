// Unit coverage for the replay healing port.

import 'package:agent_device/src/backend/platform.dart';
import 'package:agent_device/src/replay/heal.dart';
import 'package:agent_device/src/replay/session_action.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('collectReplaySelectorCandidates', () {
    test('click with bare selector returns the joined positionals', () {
      final action = const SessionAction(
        ts: 0,
        command: 'click',
        positionals: ['id=login'],
        flags: {},
      );
      expect(collectReplaySelectorCandidates(action), ['id=login']);
    });

    test('click with @ref does not generate a positional candidate', () {
      final action = const SessionAction(
        ts: 0,
        command: 'click',
        positionals: ['@e3'],
        flags: {},
      );
      expect(collectReplaySelectorCandidates(action), isEmpty);
    });

    test('recorded selectorChain in result is surfaced first', () {
      final action = const SessionAction(
        ts: 0,
        command: 'click',
        positionals: ['@e3'],
        flags: {},
        result: {
          'selectorChain': ['id=foo', 'label=Bar'],
        },
      );
      expect(collectReplaySelectorCandidates(action), ['id=foo', 'label=Bar']);
    });

    test('fill extracts the selector target', () {
      final action = const SessionAction(
        ts: 0,
        command: 'fill',
        positionals: ['id=email', 'user@example.com'],
        flags: {},
      );
      expect(collectReplaySelectorCandidates(action), ['id=email']);
    });

    test('is predicate splits off the selector portion', () {
      final action = const SessionAction(
        ts: 0,
        command: 'is',
        positionals: ['visible', 'role=button', 'label=Submit'],
        flags: {},
      );
      expect(collectReplaySelectorCandidates(action), [
        'role=button label=Submit',
      ]);
    });

    test('wait with trailing timeout strips the number', () {
      final action = const SessionAction(
        ts: 0,
        command: 'wait',
        positionals: ['id=login', '5000'],
        flags: {},
      );
      expect(collectReplaySelectorCandidates(action), ['id=login']);
    });
  });

  group('inferFillText', () {
    test('prefers result.text when present', () {
      final action = const SessionAction(
        ts: 0,
        command: 'fill',
        positionals: ['@e1'],
        flags: {},
        result: {'text': 'hello'},
      );
      expect(inferFillText(action), 'hello');
    });

    test('joins trailing positionals after @ref + refLabel', () {
      final action = const SessionAction(
        ts: 0,
        command: 'fill',
        positionals: ['@e1', 'refLabel', 'hello', 'world'],
        flags: {},
      );
      expect(inferFillText(action), 'hello world');
    });

    test('skips leading coords', () {
      final action = const SessionAction(
        ts: 0,
        command: 'fill',
        positionals: ['100', '200', 'text here'],
        flags: {},
      );
      expect(inferFillText(action), 'text here');
    });

    test('tail after selector', () {
      final action = const SessionAction(
        ts: 0,
        command: 'fill',
        positionals: ['id=email', 'user@example.com'],
        flags: {},
      );
      expect(inferFillText(action), 'user@example.com');
    });
  });

  group('healReplayAction', () {
    SnapshotNode makeNode({
      required int index,
      String? identifier,
      String? label,
      String? type,
    }) => SnapshotNode(
      index: index,
      ref: '@e$index',
      identifier: identifier,
      label: label,
      type: type,
      role: type,
      rect: const Rect(x: 0, y: 0, width: 100, height: 40),
      hittable: true,
    );

    test('rewrites a click positional to the node\'s fresh selector chain', () {
      final nodes = [
        makeNode(index: 0, type: 'Button', label: 'Login', identifier: 'login'),
      ];
      final action = const SessionAction(
        ts: 0,
        command: 'click',
        positionals: ['id=login'],
        flags: {},
      );
      final healed = healReplayAction(
        action: action,
        nodes: nodes,
        platform: AgentDeviceBackendPlatform.android,
      );
      expect(healed, isNotNull);
      expect(healed!.command, 'click');
      expect(healed.positionals, hasLength(1));
      expect(
        healed.positionals.first,
        contains('id='),
        reason: 'Expected a rebuilt selector chain.',
      );
    });

    test('returns null when no candidate resolves', () {
      final nodes = [
        makeNode(
          index: 0,
          type: 'Button',
          label: 'Logout',
          identifier: 'logout',
        ),
      ];
      final action = const SessionAction(
        ts: 0,
        command: 'click',
        positionals: ['id=does-not-exist'],
        flags: {},
      );
      expect(
        healReplayAction(
          action: action,
          nodes: nodes,
          platform: AgentDeviceBackendPlatform.android,
        ),
        isNull,
      );
    });

    test('fill preserves text and rewrites selector', () {
      final nodes = [
        makeNode(
          index: 0,
          type: 'TextField',
          identifier: 'email',
          label: 'Email',
        ),
      ];
      final action = const SessionAction(
        ts: 0,
        command: 'fill',
        positionals: ['id=email', 'user@example.com'],
        flags: {},
      );
      final healed = healReplayAction(
        action: action,
        nodes: nodes,
        platform: AgentDeviceBackendPlatform.android,
      );
      expect(healed, isNotNull);
      expect(healed!.positionals.length, 2);
      expect(healed.positionals[1], 'user@example.com');
    });

    test('non-selector commands are not healed', () {
      final nodes = [makeNode(index: 0, type: 'Button')];
      final action = const SessionAction(
        ts: 0,
        command: 'home',
        positionals: [],
        flags: {},
      );
      expect(
        healReplayAction(
          action: action,
          nodes: nodes,
          platform: AgentDeviceBackendPlatform.android,
        ),
        isNull,
      );
    });
  });
}
