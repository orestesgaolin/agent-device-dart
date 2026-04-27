// Tests for selector matching
@TestOn('vm')
library;

import 'package:agent_device/src/selectors/match.dart';
import 'package:agent_device/src/selectors/parse.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('matchesSelector', () {
    final testNode = SnapshotNode(
      index: 1,
      ref: 'e1',
      type: 'UIButton',
      label: 'Submit',
      value: 'submit',
      identifier: 'btn_submit',
      enabled: true,
      hittable: true,
      rect: Rect(x: 10, y: 20, width: 100, height: 50),
    );

    test('matches by role (normalized)', () {
      final selector = const Selector(
        raw: 'role=uibutton',
        terms: [SelectorTerm(key: 'role', value: 'uibutton')],
      );
      expect(matchesSelector(testNode, selector, 'ios'), true);
    });

    test('matches by label (case-insensitive)', () {
      final selector = const Selector(
        raw: 'label="SUBMIT"',
        terms: [SelectorTerm(key: 'label', value: 'SUBMIT')],
      );
      expect(matchesSelector(testNode, selector, 'ios'), true);
    });

    test('matches by visible flag', () {
      final selector = const Selector(
        raw: 'visible=true',
        terms: [SelectorTerm(key: 'visible', value: true)],
      );
      expect(matchesSelector(testNode, selector, 'ios'), true);
    });

    test('does not match mismatched selector', () {
      final selector = const Selector(
        raw: 'label="notfound"',
        terms: [SelectorTerm(key: 'label', value: 'notfound')],
      );
      expect(matchesSelector(testNode, selector, 'ios'), false);
    });

    test('requires all terms to match', () {
      final selector = const Selector(
        raw: 'role=uibutton label="Submit"',
        terms: [
          SelectorTerm(key: 'role', value: 'uibutton'),
          SelectorTerm(key: 'label', value: 'Submit'),
        ],
      );
      expect(matchesSelector(testNode, selector, 'ios'), true);
    });
  });

  group('isNodeVisible', () {
    test('returns true for hittable node', () {
      final node = SnapshotNode(index: 1, ref: 'e1', hittable: true);
      expect(isNodeVisible(node), true);
    });

    test('returns true for node with positive rect', () {
      final node = SnapshotNode(
        index: 1,
        ref: 'e1',
        rect: Rect(x: 0, y: 0, width: 100, height: 50),
      );
      expect(isNodeVisible(node), true);
    });

    test('returns false for node without rect', () {
      final node = SnapshotNode(index: 1, ref: 'e1');
      expect(isNodeVisible(node), false);
    });

    test('returns false for node with zero-size rect', () {
      final node = SnapshotNode(
        index: 1,
        ref: 'e1',
        rect: Rect(x: 0, y: 0, width: 0, height: 50),
      );
      expect(isNodeVisible(node), false);
    });
  });

  group('isNodeEditable', () {
    test('returns true for fillable type on iOS', () {
      final node = SnapshotNode(
        index: 1,
        ref: 'e1',
        type: 'UITextField',
        enabled: true,
      );
      expect(isNodeEditable(node, 'ios'), true);
    });

    test('returns false when disabled', () {
      final node = SnapshotNode(
        index: 1,
        ref: 'e1',
        type: 'UITextField',
        enabled: false,
      );
      expect(isNodeEditable(node, 'ios'), false);
    });

    test('returns true for EditText on Android', () {
      final node = SnapshotNode(
        index: 1,
        ref: 'e1',
        type: 'android.widget.EditText',
        enabled: true,
      );
      expect(isNodeEditable(node, 'android'), true);
    });
  });
}
