// Smoke tests for the `agent-device completion <shell>` builder.
// Each shell's script is checked for the structural pieces a working
// completion needs — subcommand list present, common flags listed,
// `--platform` value list — without depending on the user's actual
// shell being installed.

import 'package:agent_device/src/cli/commands/completion_cmd.dart';
import 'package:agent_device/src/cli/run_cli.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('buildCompletionScript', () {
    test('bash emits a complete -F definition + subcommand list', () {
      final out = buildCompletionScript('bash');
      expect(out, contains('complete -F _agent_device_complete agent-device'));
      expect(out, contains('complete -F _agent_device_complete ad'));
      expect(out, contains('snapshot'));
      expect(out, contains('install'));
      expect(out, contains('runner'));
      expect(out, contains('completion'));
      expect(out, contains('--platform'));
      expect(out, contains('ios android macos linux apple'));
    });

    test('zsh emits a #compdef line + subcommand list', () {
      final out = buildCompletionScript('zsh');
      expect(out, startsWith('#compdef agent-device ad'));
      expect(out, contains("'snapshot'"));
      expect(out, contains("'install'"));
      expect(out, contains("'completion'"));
      expect(out, contains('_arguments'));
    });

    test('fish emits per-subcommand complete lines', () {
      final out = buildCompletionScript('fish');
      expect(
        out,
        contains(
          "complete -c agent-device -f -n '__fish_use_subcommand' -a 'snapshot'",
        ),
      );
      expect(
        out,
        contains(
          "complete -c ad -f -n '__fish_use_subcommand' -a 'install'",
        ),
      );
      expect(
        out,
        contains("complete -c agent-device -l platform -x -a 'ios android"),
      );
    });

    test('rejects unknown shells', () {
      expect(
        () => buildCompletionScript('csh'),
        throwsA(isA<AppError>().having(
          (e) => e.code,
          'code',
          AppErrorCodes.invalidArgs,
        )),
      );
    });

    test('completion subcommand is registered on the runner', () {
      final runner = buildCliRunner();
      expect(runner.commands.keys, contains('completion'));
    });
  });
}
