// Tests for selector resolution
@TestOn('vm')
library;

import 'package:agent_device/src/selectors/parse.dart';
import 'package:agent_device/src/selectors/resolve.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('resolveSelectorChain', () {
    final nodes = [
      SnapshotNode(
        index: 1,
        ref: 'e1',
        type: 'UIButton',
        label: 'OK',
        enabled: true,
        hittable: true,
        depth: 1,
        rect: Rect(x: 10, y: 20, width: 50, height: 30),
      ),
      SnapshotNode(
        index: 2,
        ref: 'e2',
        type: 'UIButton',
        label: 'Cancel',
        enabled: true,
        hittable: true,
        depth: 1,
        rect: Rect(x: 70, y: 20, width: 50, height: 30),
      ),
    ];

    test('resolves unique selector', () {
      final chain = const SelectorChain(
        raw: 'label="OK"',
        selectors: [
          Selector(
            raw: 'label="OK"',
            terms: [SelectorTerm(key: 'label', value: 'OK')],
          ),
        ],
      );

      final resolution = resolveSelectorChain(
        nodes,
        chain,
        platform: 'ios',
        requireUnique: true,
      );
      expect(resolution, isNotNull);
      expect(resolution!.node.label, 'OK');
      expect(resolution.selectorIndex, 0);
      expect(resolution.matches, 1);
    });

    test('returns null when no match', () {
      final chain = const SelectorChain(
        raw: 'label="nonexistent"',
        selectors: [
          Selector(
            raw: 'label="nonexistent"',
            terms: [SelectorTerm(key: 'label', value: 'nonexistent')],
          ),
        ],
      );

      final resolution = resolveSelectorChain(
        nodes,
        chain,
        platform: 'ios',
        requireUnique: true,
      );
      expect(resolution, isNull);
    });

    test('uses fallback when first selector fails', () {
      final chain = const SelectorChain(
        raw: 'label="nonexistent" || label="Cancel"',
        selectors: [
          Selector(
            raw: 'label="nonexistent"',
            terms: [SelectorTerm(key: 'label', value: 'nonexistent')],
          ),
          Selector(
            raw: 'label="Cancel"',
            terms: [SelectorTerm(key: 'label', value: 'Cancel')],
          ),
        ],
      );

      final resolution = resolveSelectorChain(
        nodes,
        chain,
        platform: 'ios',
        requireUnique: true,
      );
      expect(resolution, isNotNull);
      expect(resolution!.node.label, 'Cancel');
      expect(resolution.selectorIndex, 1);
    });
  });

  group('findSelectorChainMatch', () {
    final nodes = [
      SnapshotNode(
        index: 1,
        ref: 'e1',
        type: 'UIButton',
        label: 'OK',
        enabled: true,
        hittable: true,
      ),
    ];

    test('finds first matching selector', () {
      final chain = const SelectorChain(
        raw: 'label="OK"',
        selectors: [
          Selector(
            raw: 'label="OK"',
            terms: [SelectorTerm(key: 'label', value: 'OK')],
          ),
        ],
      );

      final match = findSelectorChainMatch(nodes, chain, platform: 'ios');
      expect(match, isNotNull);
      expect(match!.selectorIndex, 0);
      expect(match.matches, 1);
    });

    test('returns null when no match found', () {
      final chain = const SelectorChain(
        raw: 'label="notfound"',
        selectors: [
          Selector(
            raw: 'label="notfound"',
            terms: [SelectorTerm(key: 'label', value: 'notfound')],
          ),
        ],
      );

      final match = findSelectorChainMatch(nodes, chain, platform: 'ios');
      expect(match, isNull);
    });
  });

  group('formatSelectorFailure', () {
    test('formats failure with diagnostics', () {
      final chain = const SelectorChain(
        raw: 'label="OK" || label="Cancel"',
        selectors: [],
      );
      final diagnostics = [
        const SelectorDiagnostics(selector: 'label="OK"', matches: 0),
        const SelectorDiagnostics(selector: 'label="Cancel"', matches: 0),
      ];

      final message = formatSelectorFailure(chain, diagnostics);
      expect(message, contains('did not resolve uniquely'));
      expect(message, contains('label="OK"'));
    });

    test('formats failure without diagnostics', () {
      final chain = const SelectorChain(raw: 'label="test"', selectors: []);

      final message = formatSelectorFailure(chain, []);
      expect(message, contains('Selector did not match'));
      expect(message, contains('label="test"'));
    });
  });
}
