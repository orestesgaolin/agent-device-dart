// Unit coverage for `.ad` replay parametrisation: source merging,
// shell-env filter, CLI -e parsing, and ${VAR} interpolation. Mirrors
// the upstream TS coverage in `session-replay-vars.test.ts`.

import 'package:agent_device/src/replay/replay_vars.dart';
import 'package:agent_device/src/replay/session_action.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('buildReplayVarScope', () {
    test('higher-precedence layers override lower ones', () {
      final scope = buildReplayVarScope(
        const ReplayVarSources(
          builtins: {'AD_SESSION': 'default'},
          fileEnv: {'APP': 'dev'},
          shellEnv: {'APP': 'staging'},
          cliEnv: {'APP': 'prod'},
        ),
      );
      expect(scope.values['AD_SESSION'], 'default');
      expect(scope.values['APP'], 'prod');
    });

    test('untrusted layers cannot define AD_* keys', () {
      expect(
        () => buildReplayVarScope(
          const ReplayVarSources(fileEnv: {'AD_SESSION': 'evil'}),
        ),
        throwsA(_appErr(AppErrorCodes.invalidArgs)),
      );
      expect(
        () => buildReplayVarScope(
          const ReplayVarSources(shellEnv: {'AD_PLATFORM': 'evil'}),
        ),
        throwsA(_appErr(AppErrorCodes.invalidArgs)),
      );
      expect(
        () => buildReplayVarScope(
          const ReplayVarSources(cliEnv: {'AD_FILENAME': 'evil'}),
        ),
        throwsA(_appErr(AppErrorCodes.invalidArgs)),
      );
    });

    test('builtins layer can legitimately use AD_*', () {
      final scope = buildReplayVarScope(
        const ReplayVarSources(builtins: {'AD_PLATFORM': 'ios'}),
      );
      expect(scope.values['AD_PLATFORM'], 'ios');
    });
  });

  group('collectReplayShellEnv', () {
    test('keeps AD_VAR_* entries with the prefix stripped', () {
      final result = collectReplayShellEnv({
        'AD_VAR_APP': 'dev',
        'AD_VAR_REGION': 'eu',
        'PATH': '/bin',
        'AD_TOKEN': 'secret-not-imported',
      });
      expect(result, equals({'APP': 'dev', 'REGION': 'eu'}));
    });

    test('drops stripped keys that re-enter the AD_* namespace', () {
      // AD_VAR_AD_SESSION would strip to AD_SESSION — must not leak.
      final result = collectReplayShellEnv({'AD_VAR_AD_SESSION': 'evil'});
      expect(result, isEmpty);
    });

    test('drops invalid key shapes', () {
      final result = collectReplayShellEnv({
        'AD_VAR_lowercase': 'no',
        'AD_VAR_': 'empty-suffix',
        'AD_VAR_VALID_KEY': 'yes',
      });
      expect(result, equals({'VALID_KEY': 'yes'}));
    });
  });

  group('parseReplayCliEnvEntries', () {
    test('parses KEY=VALUE entries', () {
      final result = parseReplayCliEnvEntries(['APP=dev', 'REGION=eu']);
      expect(result, equals({'APP': 'dev', 'REGION': 'eu'}));
    });

    test('rejects entries without =', () {
      expect(
        () => parseReplayCliEnvEntries(['APPdev']),
        throwsA(_appErr(AppErrorCodes.invalidArgs)),
      );
    });

    test('rejects invalid keys', () {
      expect(
        () => parseReplayCliEnvEntries(['lowercase=v']),
        throwsA(_appErr(AppErrorCodes.invalidArgs)),
      );
      expect(
        () => parseReplayCliEnvEntries(['1NUMERIC=v']),
        throwsA(_appErr(AppErrorCodes.invalidArgs)),
      );
    });

    test('rejects AD_* namespace', () {
      expect(
        () => parseReplayCliEnvEntries(['AD_SESSION=evil']),
        throwsA(_appErr(AppErrorCodes.invalidArgs)),
      );
    });

    test('values may contain `=`', () {
      expect(parseReplayCliEnvEntries(['KEY=a=b=c']), equals({'KEY': 'a=b=c'}));
    });
  });

  group('resolveReplayString', () {
    final scope = buildReplayVarScope(
      const ReplayVarSources(
        builtins: {'AD_PLATFORM': 'ios'},
        cliEnv: {'APP': 'dev'},
      ),
    );

    test('substitutes a known variable', () {
      expect(
        resolveReplayString(r'open ${APP}', scope, file: 'x.ad', line: 1),
        equals('open dev'),
      );
    });

    test('uses default when var is unset', () {
      expect(
        resolveReplayString(
          r'open ${MISSING:-fallback}',
          scope,
          file: 'x.ad',
          line: 1,
        ),
        equals('open fallback'),
      );
    });

    test(r'`\${...}` produces a literal `${`', () {
      expect(
        resolveReplayString(r'literal \${APP}', scope, file: 'x.ad', line: 1),
        equals(r'literal ${APP}'),
      );
    });

    test('throws with file:line on unresolved variables', () {
      try {
        resolveReplayString(r'${MISSING}', scope, file: 'x.ad', line: 7);
        fail('expected throw');
      } on AppError catch (e) {
        expect(e.code, AppErrorCodes.invalidArgs);
        expect(e.message, contains('x.ad:7'));
        expect(e.message, contains(r'${MISSING}'));
      }
    });

    test('substitutes built-ins', () {
      expect(
        resolveReplayString(
          r'platform=${AD_PLATFORM}',
          scope,
          file: 'x.ad',
          line: 1,
        ),
        equals('platform=ios'),
      );
    });

    test('default value supports escaped braces and backslashes', () {
      expect(
        resolveReplayString(
          r'${MISSING:-with\}brace}',
          scope,
          file: 'x.ad',
          line: 1,
        ),
        equals('with}brace'),
      );
    });
  });

  group('resolveReplayAction', () {
    final scope = buildReplayVarScope(
      const ReplayVarSources(cliEnv: {'APP': 'com.example'}),
    );

    test('resolves positionals + flags', () {
      final action = const SessionAction(
        ts: 0,
        command: 'open',
        positionals: [r'${APP}'],
        flags: {'note': r'launching ${APP}', 'count': 3},
      );
      final resolved = resolveReplayAction(
        action,
        scope,
        file: 'x.ad',
        line: 4,
      );
      expect(resolved.positionals, equals(['com.example']));
      expect(resolved.flags['note'], equals('launching com.example'));
      expect(resolved.flags['count'], equals(3));
    });

    test('resolves SessionRuntimeHints fields', () {
      final action = const SessionAction(
        ts: 0,
        command: 'open',
        positionals: [],
        flags: {},
        runtime: SessionRuntimeHints(
          metroHost: r'${APP}.local',
          launchUrl: r'app://${APP}',
        ),
      );
      final resolved = resolveReplayAction(
        action,
        scope,
        file: 'x.ad',
        line: 1,
      );
      expect(resolved.runtime?.metroHost, 'com.example.local');
      expect(resolved.runtime?.launchUrl, 'app://com.example');
    });
  });

  group('actionsContainInterpolation', () {
    test(r'detects ${} in positionals, flags, and runtime', () {
      final empty = const SessionAction(
        ts: 0,
        command: 'open',
        positionals: ['plain'],
        flags: {},
      );
      expect(actionsContainInterpolation([empty]), isFalse);

      final inPositional = const SessionAction(
        ts: 0,
        command: 'open',
        positionals: [r'${APP}'],
        flags: {},
      );
      expect(actionsContainInterpolation([inPositional]), isTrue);

      final inFlag = const SessionAction(
        ts: 0,
        command: 'fill',
        positionals: [],
        flags: {'value': r'${APP}'},
      );
      expect(actionsContainInterpolation([inFlag]), isTrue);

      final inRuntime = const SessionAction(
        ts: 0,
        command: 'open',
        positionals: [],
        flags: {},
        runtime: SessionRuntimeHints(launchUrl: r'app://${APP}'),
      );
      expect(actionsContainInterpolation([inRuntime]), isTrue);
    });
  });
}

Matcher _appErr(String code) =>
    isA<AppError>().having((e) => e.code, 'code', code);
