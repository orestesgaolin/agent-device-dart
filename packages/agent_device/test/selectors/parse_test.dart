// Tests for selector parsing (port of agent-device selector DSL tests)
@TestOn('vm')
library;

import 'package:agent_device/src/selectors/parse.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('parseSelectorChain', () {
    test('parses simple single selector', () {
      final chain = parseSelectorChain('role=button');
      expect(chain.selectors, hasLength(1));
      expect(chain.selectors[0].terms, hasLength(1));
      expect(chain.selectors[0].terms[0].key, 'role');
      expect(chain.selectors[0].terms[0].value, 'button');
    });

    test('parses selector with multiple terms', () {
      final chain = parseSelectorChain('role=button label="Submit"');
      expect(chain.selectors, hasLength(1));
      expect(chain.selectors[0].terms, hasLength(2));
      expect(chain.selectors[0].terms[0].key, 'role');
      expect(chain.selectors[0].terms[0].value, 'button');
      expect(chain.selectors[0].terms[1].key, 'label');
      expect(chain.selectors[0].terms[1].value, 'Submit');
    });

    test('parses selector chain with fallback (||)', () {
      final chain = parseSelectorChain(
        'id=submit || label="OK" || role=button',
      );
      expect(chain.selectors, hasLength(3));
      expect(chain.selectors[0].terms[0].value, 'submit');
      expect(chain.selectors[1].terms[0].value, 'OK');
      expect(chain.selectors[2].terms[0].value, 'button');
    });

    test('parses boolean predicates', () {
      final chain = parseSelectorChain('visible=true');
      expect(chain.selectors[0].terms[0].key, 'visible');
      expect(chain.selectors[0].terms[0].value, true);
    });

    test('parses boolean shorthand', () {
      final chain = parseSelectorChain('visible');
      expect(chain.selectors[0].terms[0].key, 'visible');
      expect(chain.selectors[0].terms[0].value, true);
    });

    test('throws on empty expression', () {
      expect(
        () => parseSelectorChain(''),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            AppErrorCodes.invalidArgs,
          ),
        ),
      );
    });

    test('throws on unclosed quote', () {
      expect(
        () => parseSelectorChain('label="unclosed'),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            AppErrorCodes.invalidArgs,
          ),
        ),
      );
    });
  });

  group('isSelectorToken', () {
    test('recognizes key=value as token', () {
      expect(isSelectorToken('role=button'), true);
      expect(isSelectorToken('label="text"'), true);
    });

    test('recognizes boolean shorthands', () {
      expect(isSelectorToken('visible'), true);
      expect(isSelectorToken('hidden'), true);
    });

    test('recognizes fallback operator', () {
      expect(isSelectorToken('||'), true);
    });

    test('rejects non-selector tokens', () {
      expect(isSelectorToken('random'), false);
      expect(isSelectorToken('foo=bar'), false);
    });
  });

  group('splitSelectorFromArgs', () {
    test('extracts selector from args', () {
      final result = splitSelectorFromArgs([
        'role=button',
        'label="OK"',
        'extra',
      ]);
      expect(result, isNotNull);
      expect(result!.selectorExpression, 'role=button label="OK"');
      expect(result.rest, ['extra']);
    });

    test('returns null when no selector tokens', () {
      final result = splitSelectorFromArgs(['foo', 'bar']);
      expect(result, isNull);
    });

    test('returns null for empty args', () {
      final result = splitSelectorFromArgs([]);
      expect(result, isNull);
    });
  });

  group('tryParseSelectorChain', () {
    test('returns chain on valid input', () {
      final chain = tryParseSelectorChain('role=button');
      expect(chain, isNotNull);
      expect(chain!.selectors, hasLength(1));
    });

    test('returns null on invalid input', () {
      final chain = tryParseSelectorChain('invalid syntax @@');
      expect(chain, isNull);
    });
  });
}
