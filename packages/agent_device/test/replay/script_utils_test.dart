/// Tests for replay script utilities.
library;

import 'package:agent_device/src/replay/script_utils.dart';
import 'package:agent_device/src/replay/session_action.dart';
import 'package:test/test.dart';

void main() {
  group('formatScriptArg', () {
    test('quotes strings with spaces', () {
      expect(formatScriptArg('hello world'), equals('"hello world"'));
    });

    test('quotes non-structural bare tokens', () {
      // formatScriptArg only keeps structural tokens (@refs, numbers) bare
      expect(formatScriptArg('hello'), equals('"hello"'));
    });

    test('keeps numeric tokens unquoted', () {
      expect(formatScriptArg('123'), equals('123'));
    });

    test('keeps negative numbers unquoted', () {
      expect(formatScriptArg('-42'), equals('-42'));
    });

    test('keeps selector refs unquoted', () {
      expect(formatScriptArg('@mySelector'), equals('@mySelector'));
    });

    test('quotes complex selectors with equals', () {
      final result = formatScriptArg('label=Settings');
      expect(result, equals('"label=Settings"'));
    });
  });

  group('formatScriptStringLiteral', () {
    test('quotes all strings', () {
      expect(formatScriptStringLiteral('hello'), equals('"hello"'));
    });

    test('escapes quotes in strings', () {
      final result = formatScriptStringLiteral('say "hello"');
      expect(result, contains('\\"'));
    });

    test('escapes backslashes', () {
      final result = formatScriptStringLiteral('path\\to\\file');
      expect(result, contains('\\\\'));
    });
  });

  group('formatScriptArgQuoteIfNeeded', () {
    test('keeps bare tokens unquoted', () {
      expect(formatScriptArgQuoteIfNeeded('hello'), equals('hello'));
    });

    test('quotes tokens with spaces', () {
      expect(
        formatScriptArgQuoteIfNeeded('hello world'),
        equals('"hello world"'),
      );
    });
  });

  group('isClickLikeCommand', () {
    test('recognizes click', () {
      expect(isClickLikeCommand('click'), isTrue);
    });

    test('recognizes press', () {
      expect(isClickLikeCommand('press'), isTrue);
    });

    test('rejects other commands', () {
      expect(isClickLikeCommand('swipe'), isFalse);
      expect(isClickLikeCommand('tap'), isFalse);
      expect(isClickLikeCommand('open'), isFalse);
    });
  });

  group('appendScriptSeriesFlags', () {
    test('appends click flags', () {
      final action = const SessionAction(
        ts: 0,
        command: 'click',
        positionals: [],
        flags: {'count': 3, 'intervalMs': 100, 'holdMs': 500},
      );
      final parts = ['click', 'target'];
      appendScriptSeriesFlags(parts, action);

      expect(parts, contains('--count'));
      expect(parts, contains('3'));
      expect(parts, contains('--interval-ms'));
      expect(parts, contains('100'));
      expect(parts, contains('--hold-ms'));
      expect(parts, contains('500'));
    });

    test('appends click double-tap flag', () {
      final action = const SessionAction(
        ts: 0,
        command: 'click',
        positionals: [],
        flags: {'doubleTap': true},
      );
      final parts = ['click'];
      appendScriptSeriesFlags(parts, action);

      expect(parts, contains('--double-tap'));
    });

    test('appends click button flag', () {
      final action = const SessionAction(
        ts: 0,
        command: 'press',
        positionals: [],
        flags: {'clickButton': 'secondary'},
      );
      final parts = ['press'];
      appendScriptSeriesFlags(parts, action);

      expect(parts, contains('--button'));
      expect(parts, contains('secondary'));
    });

    test('skips primary button (default)', () {
      final action = const SessionAction(
        ts: 0,
        command: 'click',
        positionals: [],
        flags: {'clickButton': 'primary'},
      );
      final parts = ['click'];
      appendScriptSeriesFlags(parts, action);

      expect(parts, isNot(contains('--button')));
    });

    test('appends swipe flags', () {
      final action = const SessionAction(
        ts: 0,
        command: 'swipe',
        positionals: [],
        flags: {'count': 2, 'pauseMs': 200, 'pattern': 'ping-pong'},
      );
      final parts = ['swipe'];
      appendScriptSeriesFlags(parts, action);

      expect(parts, contains('--count'));
      expect(parts, contains('2'));
      expect(parts, contains('--pause-ms'));
      expect(parts, contains('200'));
      expect(parts, contains('--pattern'));
      expect(parts, contains('ping-pong'));
    });

    test('appends type flags', () {
      final action = const SessionAction(
        ts: 0,
        command: 'type',
        positionals: [],
        flags: {'delayMs': 50},
      );
      final parts = ['type'];
      appendScriptSeriesFlags(parts, action);

      expect(parts, contains('--delay-ms'));
      expect(parts, contains('50'));
    });
  });

  group('parseReplaySeriesFlags', () {
    test('parses click flags', () {
      final result = parseReplaySeriesFlags('click', [
        'target',
        '--count',
        '3',
        '--interval-ms',
        '100',
      ]);

      expect(result.positionals, equals(['target']));
      expect(result.flags['count'], equals(3));
      expect(result.flags['intervalMs'], equals(100));
    });

    test('parses swipe flags', () {
      final result = parseReplaySeriesFlags('swipe', [
        '--count',
        '2',
        '--pattern',
        'one-way',
      ]);

      expect(result.flags['count'], equals(2));
      expect(result.flags['pattern'], equals('one-way'));
    });

    test('parses type flags', () {
      final result = parseReplaySeriesFlags('type', [
        'hello',
        '--delay-ms',
        '75',
      ]);

      expect(result.positionals, equals(['hello']));
      expect(result.flags['delayMs'], equals(75));
    });

    test('ignores invalid flag values', () {
      final result = parseReplaySeriesFlags('click', [
        '--count',
        'invalid',
        'target',
      ]);

      expect(result.flags['count'], isNull);
      expect(result.positionals, contains('target'));
    });
  });

  group('parseReplayRuntimeFlags', () {
    test('parses platform', () {
      final result = parseReplayRuntimeFlags(['--platform', 'ios']);

      expect(result.flags['platform'], equals('ios'));
    });

    test('parses metro config', () {
      final result = parseReplayRuntimeFlags([
        '--metro-host',
        'localhost',
        '--metro-port',
        '8081',
        '--bundle-url',
        'http://localhost:8081/index.bundle',
      ]);

      expect(result.flags['metroHost'], equals('localhost'));
      expect(result.flags['metroPort'], equals(8081));
      expect(
        result.flags['bundleUrl'],
        equals('http://localhost:8081/index.bundle'),
      );
    });

    test('parses launch URL', () {
      final result = parseReplayRuntimeFlags([
        '--launch-url',
        'myapp://deep/link',
      ]);

      expect(result.flags['launchUrl'], equals('myapp://deep/link'));
    });

    test('handles positionals and flags mixed', () {
      final result = parseReplayRuntimeFlags([
        'com.example.app',
        '--platform',
        'android',
        'other-arg',
      ]);

      expect(result.positionals, contains('com.example.app'));
      expect(result.positionals, contains('other-arg'));
      expect(result.flags['platform'], equals('android'));
    });

    test('ignores invalid platform', () {
      final result = parseReplayRuntimeFlags(['--platform', 'windows']);

      expect(result.flags['platform'], isNull);
    });

    test('ignores invalid metro-port', () {
      final result = parseReplayRuntimeFlags(['--metro-port', 'invalid']);

      expect(result.flags['metroPort'], isNull);
    });
  });

  group('appendRuntimeHintFlags', () {
    test('appends platform flag', () {
      final parts = <String>[];
      appendRuntimeHintFlags(parts, {'platform': 'ios'});

      expect(parts, equals(['--platform', 'ios']));
    });

    test('appends metro config flags', () {
      final parts = <String>[];
      appendRuntimeHintFlags(parts, {
        'metroHost': 'localhost',
        'metroPort': 8081,
        'bundleUrl': 'http://localhost:8081',
        'launchUrl': 'myapp://link',
      });

      expect(parts, contains('--metro-host'));
      expect(parts, contains('localhost'));
      expect(parts, contains('--metro-port'));
      expect(parts, contains('8081'));
      expect(parts, contains('--bundle-url'));
      expect(parts, contains('--launch-url'));
    });

    test('ignores null and empty values', () {
      final parts = <String>[];
      appendRuntimeHintFlags(parts, {'metroHost': '', 'platform': null});

      expect(parts, isEmpty);
    });
  });
}
