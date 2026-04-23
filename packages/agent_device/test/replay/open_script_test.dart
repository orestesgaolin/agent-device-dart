/// Tests for open action script parsing and formatting.
library;

import 'package:agent_device/src/replay/open_script.dart';
import 'package:agent_device/src/replay/session_action.dart';
import 'package:test/test.dart';

void main() {
  group('parseReplayOpenFlags', () {
    test('parses relaunch flag', () {
      final result = parseReplayOpenFlags(['com.example.app', '--relaunch']);

      expect(result.positionals, equals(['com.example.app']));
      expect(result.flags['relaunch'], isTrue);
    });

    test('parses runtime hints', () {
      final result = parseReplayOpenFlags([
        'com.example.app',
        '--platform',
        'ios',
        '--metro-host',
        'localhost',
        '--metro-port',
        '8081',
      ]);

      expect(result.positionals, equals(['com.example.app']));
      expect(result.runtime?.platform, equals('ios'));
      expect(result.runtime?.metroHost, equals('localhost'));
      expect(result.runtime?.metroPort, equals(8081));
    });

    test('combines relaunch and runtime hints', () {
      final result = parseReplayOpenFlags([
        'app',
        '--relaunch',
        '--platform',
        'android',
      ]);

      expect(result.flags['relaunch'], isTrue);
      expect(result.runtime?.platform, equals('android'));
    });

    test('returns null runtime if no hints present', () {
      final result = parseReplayOpenFlags(['com.example.app']);

      expect(result.positionals, equals(['com.example.app']));
      expect(result.flags['relaunch'], isNull);
      expect(result.runtime, isNull);
    });

    test('parses bundle URL and launch URL', () {
      final result = parseReplayOpenFlags([
        'app',
        '--bundle-url',
        'http://localhost:8081/index.bundle',
        '--launch-url',
        'myapp://deep/link',
      ]);

      expect(
        result.runtime?.bundleUrl,
        equals('http://localhost:8081/index.bundle'),
      );
      expect(result.runtime?.launchUrl, equals('myapp://deep/link'));
    });
  });

  group('appendOpenActionScriptArgs', () {
    test('appends positionals and relaunch flag', () {
      final action = const SessionAction(
        ts: 0,
        command: 'open',
        positionals: ['com.example.app'],
        flags: {'relaunch': true},
      );
      final parts = ['open'];
      appendOpenActionScriptArgs(parts, action);

      expect(parts, contains('"com.example.app"'));
      expect(parts, contains('--relaunch'));
    });

    test('appends runtime hints', () {
      final action = const SessionAction(
        ts: 0,
        command: 'open',
        positionals: ['app'],
        flags: {},
        runtime: SessionRuntimeHints(
          platform: 'ios',
          metroHost: 'localhost',
          metroPort: 8081,
        ),
      );
      final parts = ['open'];
      appendOpenActionScriptArgs(parts, action);

      expect(parts, contains('"app"'));
      expect(parts, contains('--platform'));
      expect(parts, contains('ios'));
      expect(parts, contains('--metro-host'));
      expect(parts, contains('localhost'));
      expect(parts, contains('--metro-port'));
      expect(parts, contains('8081'));
    });

    test('handles multiple positionals', () {
      final action = const SessionAction(
        ts: 0,
        command: 'open',
        positionals: ['com.example.app', 'extra arg'],
        flags: {},
      );
      final parts = ['open'];
      appendOpenActionScriptArgs(parts, action);

      expect(parts.length, greaterThanOrEqualTo(2));
      expect(parts, contains('"com.example.app"'));
    });

    test('omits runtime hints if null', () {
      final action = const SessionAction(
        ts: 0,
        command: 'open',
        positionals: ['app'],
        flags: {},
        runtime: null,
      );
      final parts = ['open'];
      appendOpenActionScriptArgs(parts, action);

      expect(parts, equals(['open', '"app"']));
      expect(parts, isNot(contains('--platform')));
    });
  });

  group('SessionRuntimeHints', () {
    test('copyWith creates new instance', () {
      final original = const SessionRuntimeHints(
        platform: 'ios',
        metroHost: 'localhost',
      );

      final modified = original.copyWith(metroPort: 8081);

      expect(modified.platform, equals('ios'));
      expect(modified.metroHost, equals('localhost'));
      expect(modified.metroPort, equals(8081));
      expect(original.metroPort, isNull);
    });

    test('toJson serializes all fields', () {
      final hints = const SessionRuntimeHints(
        platform: 'android',
        metroHost: 'localhost',
        metroPort: 8081,
        bundleUrl: 'http://localhost:8081',
        launchUrl: 'myapp://link',
      );

      final json = hints.toJson();

      expect(json['platform'], equals('android'));
      expect(json['metroHost'], equals('localhost'));
      expect(json['metroPort'], equals(8081));
      expect(json['bundleUrl'], equals('http://localhost:8081'));
      expect(json['launchUrl'], equals('myapp://link'));
    });

    test('toJson omits null fields', () {
      final hints = const SessionRuntimeHints(platform: 'ios');

      final json = hints.toJson();

      expect(json.length, equals(1));
      expect(json.containsKey('platform'), isTrue);
      expect(json.containsKey('metroHost'), isFalse);
    });
  });
}
