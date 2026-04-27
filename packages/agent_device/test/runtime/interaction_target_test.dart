import 'package:agent_device/agent_device.dart';
import 'package:agent_device/src/runtime/interaction_target.dart';
import 'package:test/test.dart';

void main() {
  group('InteractionTarget.parseArgs', () {
    test('two integers become a PointTarget', () {
      final t = InteractionTarget.parseArgs(['100', '250']);
      expect(t, isA<PointTarget>());
      final pt = t! as PointTarget;
      expect(pt.point.x, 100);
      expect(pt.point.y, 250);
    });

    test('@ref becomes a RefTarget and strips the @', () {
      final t = InteractionTarget.parseArgs(['@e3']);
      expect(t, isA<RefTarget>());
      expect((t! as RefTarget).ref, 'e3');
    });

    test('selector-syntax becomes a SelectorTarget', () {
      final t = InteractionTarget.parseArgs(['label=Submit']);
      expect(t, isA<SelectorTarget>());
      expect((t! as SelectorTarget).source, 'label=Submit');
    });

    test('multi-token selector rejoins with spaces (implicit AND)', () {
      // Terms inside one selector are space-separated (implicit AND).
      final t = InteractionTarget.parseArgs(['label=Submit', 'role=button']);
      expect(t, isA<SelectorTarget>());
      final src = (t! as SelectorTarget).source;
      expect(src, 'label=Submit role=button');
    });

    test('|| fallback selector across tokens', () {
      final t = InteractionTarget.parseArgs([
        'label=Cancel',
        '||',
        'label=Close',
      ]);
      expect(t, isA<SelectorTarget>());
      expect((t! as SelectorTarget).chain.selectors, hasLength(2));
    });

    test('one-integer positional does NOT parse as a point', () {
      // Falls through to selector parsing (which fails) → null.
      expect(InteractionTarget.parseArgs(['100']), isNull);
    });

    test('empty args returns null', () {
      expect(InteractionTarget.parseArgs(const []), isNull);
    });
  });

  group('InteractionTarget.parse (single string)', () {
    test('@ref form', () {
      final t = InteractionTarget.parse('@e5');
      expect(t, isA<RefTarget>());
      expect((t as RefTarget).ref, 'e5');
    });

    test('selector form', () {
      final t = InteractionTarget.parse('label="Save changes"');
      expect(t, isA<SelectorTarget>());
    });

    test('empty input throws ArgumentError', () {
      expect(() => InteractionTarget.parse(''), throwsArgumentError);
    });
  });

  group('IsPredicateResult.exists bug regression', () {
    test('is predicate "exists" passes when node is resolved', () {
      // Regression: phase 1 is_predicates.dart had no `case 'exists'` —
      // always returned pass=false. Verified against a minimal snapshot.
      final node = SnapshotNode(
        index: 0,
        ref: 'e0',
        type: 'android.widget.Button',
        label: 'Submit',
        value: null,
        identifier: null,
        rect: Rect(x: 0, y: 0, width: 100, height: 40),
        enabled: true,
        selected: false,
        hittable: true,
        depth: 0,
        parentIndex: null,
        pid: null,
        bundleId: null,
        appName: null,
        windowTitle: null,
        surface: null,
        hiddenContentAbove: null,
        hiddenContentBelow: null,
      );
      final result = evaluateIsPredicate(
        predicate: 'exists',
        node: node,
        nodes: [node],
        platform: 'android',
      );
      expect(result.pass, isTrue);
    });
  });
}
