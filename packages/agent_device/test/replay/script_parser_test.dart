/// Tests for replay script parser.
library;

import 'package:agent_device/src/replay/script.dart';
import 'package:test/test.dart';

void main() {
  group('parseReplayScript', () {
    test('parses basic android settings script', () {
      final script =
          '''# Dogfood Android Settings flow through the replay suite runner.
context platform=android
open settings --relaunch
appstate
snapshot -i
is exists "label=Settings"
click "label=Settings"
back
wait 1000
snapshot -i
''';

      final actions = parseReplayScript(script);

      expect(actions, isNotEmpty);
      expect(actions[0].command, equals('open'));
      expect(actions[1].command, equals('appstate'));
      expect(actions[2].command, equals('snapshot'));
      expect(actions[2].flags['snapshotInteractiveOnly'], isTrue);
      expect(actions[3].command, equals('is'));
      expect(actions[4].command, equals('click'));
      expect(actions[5].command, equals('back'));
      expect(actions[6].command, equals('wait'));
    });

    test('skips empty lines and comments', () {
      final script = '''# This is a comment
open app

# Another comment

snapshot -i''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(2));
      expect(actions[0].command, equals('open'));
      expect(actions[1].command, equals('snapshot'));
    });

    test('parses snapshot flags', () {
      final script = '''snapshot -i -c -d 5 -s myScope --raw''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final snap = actions[0];
      expect(snap.command, equals('snapshot'));
      expect(snap.flags['snapshotInteractiveOnly'], isTrue);
      expect(snap.flags['snapshotCompact'], isTrue);
      expect(snap.flags['snapshotDepth'], equals(5));
      expect(snap.flags['snapshotScope'], equals('myScope'));
      expect(snap.flags['snapshotRaw'], isTrue);
    });

    test('parses open action with relaunch and platform', () {
      final script = '''open com.example.app --relaunch --platform ios''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final open = actions[0];
      expect(open.command, equals('open'));
      expect(open.positionals, containsAll(['com.example.app']));
      expect(open.flags['relaunch'], isTrue);
      expect(open.runtime?.platform, equals('ios'));
    });

    test('parses click action with selector', () {
      final script = '''click "label=Settings"''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final click = actions[0];
      expect(click.command, equals('click'));
      expect(click.positionals, equals(['label=Settings']));
    });

    test('parses click action with coordinates', () {
      final script = '''click 100 200''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final click = actions[0];
      expect(click.command, equals('click'));
      expect(click.positionals, equals(['100', '200']));
    });

    test('parses click with flags', () {
      final script = '''click "label=Btn" --count 3 --interval-ms 100''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final click = actions[0];
      expect(click.flags['count'], equals(3));
      expect(click.flags['intervalMs'], equals(100));
    });

    test('parses fill action', () {
      final script = '''fill "id=input" "hello world"''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final fill = actions[0];
      expect(fill.command, equals('fill'));
      expect(fill.positionals[0], equals('id=input'));
      expect(fill.positionals[1], equals('hello world'));
    });

    test('parses type action with delay', () {
      final script = '''type "some text" --delay-ms 50''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final type = actions[0];
      expect(type.command, equals('type'));
      expect(type.flags['delayMs'], equals(50));
    });

    test('parses swipe action with pattern', () {
      final script = '''swipe 100 200 300 400 --pattern ping-pong''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final swipe = actions[0];
      expect(swipe.command, equals('swipe'));
      expect(swipe.flags['pattern'], equals('ping-pong'));
    });

    test('parses record action with flags', () {
      final script = '''record start --fps 30 --quality 80 --hide-touches''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final record = actions[0];
      expect(record.command, equals('record'));
      expect(record.positionals[0], equals('start'));
      expect(record.flags['fps'], equals(30));
      expect(record.flags['quality'], equals(80));
      expect(record.flags['hideTouches'], isTrue);
    });

    test('parses screenshot action', () {
      final script = '''screenshot --fullscreen --max-size 1024''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final screenshot = actions[0];
      expect(screenshot.command, equals('screenshot'));
      expect(screenshot.flags['screenshotFullscreen'], isTrue);
      expect(screenshot.flags['screenshotMaxSize'], equals(1024));
    });

    test('parses get action with selector', () {
      final script = '''get text @selector myLabel''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      final get = actions[0];
      expect(get.command, equals('get'));
      expect(get.positionals[0], equals('text'));
      expect(get.positionals[1], equals('@selector'));
      expect(get.result?['refLabel'], equals('myLabel'));
    });

    test('parses quoted strings correctly', () {
      final script = '''click "label=\\"Multi Word\\""''';

      final actions = parseReplayScript(script);

      expect(actions.length, equals(1));
      expect(actions[0].positionals[0], equals('label="Multi Word"'));
    });

    test('quoted strings honour the full JSON escape grammar', () {
      // Tab + newline + unicode escape; the previous hand-rolled
      // `_parseJsonString` only handled `\"` and `\\`.
      final script = r'click "tab\there\nline nbsp"';
      final actions = parseReplayScript(script);
      expect(actions, hasLength(1));
      expect(actions[0].positionals[0], equals('tab\there\nline nbsp'));
    });

    test('all actions have valid ts (timestamp)', () {
      final script = '''open app
snapshot
click btn''';

      final actions = parseReplayScript(script);

      for (final action in actions) {
        expect(action.ts, greaterThan(0));
        expect(
          action.ts,
          lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch + 1000),
        );
      }
    });
  });

  group('readReplayScriptMetadata', () {
    test('reads platform from context header', () {
      final script = '''context platform=ios
open app
snapshot''';

      final metadata = readReplayScriptMetadata(script);

      expect(metadata.platform, equals('ios'));
      expect(metadata.timeoutMs, isNull);
      expect(metadata.retries, isNull);
    });

    test('reads timeout and retries', () {
      final script = '''context platform=android timeout=30000 retries=3
open app''';

      final metadata = readReplayScriptMetadata(script);

      expect(metadata.platform, equals('android'));
      expect(metadata.timeoutMs, equals(30000));
      expect(metadata.retries, equals(3));
    });

    test('stops reading metadata after non-context line', () {
      final script = '''context platform=ios
open app
context platform=android''';

      final metadata = readReplayScriptMetadata(script);

      expect(metadata.platform, equals('ios'));
    });

    test('ignores invalid platform values', () {
      final script = '''context platform=windows
open app''';

      final metadata = readReplayScriptMetadata(script);

      expect(metadata.platform, isNull);
    });

    test('ignores negative timeout/retries', () {
      final script = '''context timeout=-100 retries=-1
open app''';

      final metadata = readReplayScriptMetadata(script);

      expect(metadata.timeoutMs, isNull);
      expect(metadata.retries, isNull);
    });

    test('parses timeout=0 as invalid', () {
      final script = '''context timeout=0
open app''';

      final metadata = readReplayScriptMetadata(script);

      expect(metadata.timeoutMs, isNull);
    });

    test('parses retries=0 as valid', () {
      final script = '''context retries=0
open app''';

      final metadata = readReplayScriptMetadata(script);

      expect(metadata.retries, equals(0));
    });

    test('only parses first platform value if duplicated on same line', () {
      final script = '''context platform=ios platform=android
open app''';

      final metadata = readReplayScriptMetadata(script);
      // The regex only captures the first match, so this doesn't throw
      expect(metadata.platform, equals('ios'));
    });
  });

  group('env directives', () {
    test('parses env KEY=VALUE before context', () {
      final script = 'env APP=dev\nenv REGION=eu\ncontext platform=ios\nhome\n';
      final metadata = readReplayScriptMetadata(script);
      expect(metadata.env, equals({'APP': 'dev', 'REGION': 'eu'}));
      expect(metadata.platform, equals('ios'));
    });

    test('quoted values support whitespace/escapes via JSON decoding', () {
      final script = 'env GREETING="hello world\\n"\nhome\n';
      final metadata = readReplayScriptMetadata(script);
      expect(metadata.env, equals({'GREETING': 'hello world\n'}));
    });

    test('rejects AD_* env keys', () {
      expect(
        () => readReplayScriptMetadata('env AD_SESSION=evil\nhome\n'),
        _appErr(),
      );
    });

    test('rejects duplicate env directives', () {
      expect(
        () => readReplayScriptMetadata('env APP=a\nenv APP=b\nhome\n'),
        _appErr(),
      );
    });

    test('rejects invalid key shapes', () {
      expect(
        () => readReplayScriptMetadata('env lowercase=v\nhome\n'),
        _appErr(),
      );
    });

    test('parseReplayScript rejects env after first action', () {
      final script = 'home\nenv APP=v\n';
      expect(() => parseReplayScript(script), _appErr());
    });

    test('parseReplayScriptDetailed surfaces 1-based line numbers', () {
      final script =
          'env APP=dev\n# comment\n\nopen \${APP}\n# trailer\nhome\n';
      final parsed = parseReplayScriptDetailed(script);
      expect(parsed.actions, hasLength(2));
      expect(parsed.actionLines, equals([4, 6]));
    });
  });
}

Matcher _appErr() => throwsA(isA<Object>());
