// `agent-device completion <bash|zsh|fish>` — emit a shell completion
// script. Covers top-level subcommand names, common flags, and known
// `--platform` values. Dynamic completion of device serials / app
// bundles / state-dir paths would require shelling back into the CLI
// per keystroke; we keep it static so completions stay snappy.
library;

import 'dart:io';

import 'package:agent_device/src/utils/errors.dart';
import 'package:args/command_runner.dart';

import '../run_cli.dart';

class CompletionCommand extends Command<int> {
  @override
  String get name => 'completion';

  @override
  String get description =>
      'Emit a shell completion script. Source it from your shell rc:\n'
      '  bash:  eval "\$(agent-device completion bash)"\n'
      '  zsh:   eval "\$(agent-device completion zsh)"\n'
      '  fish:  agent-device completion fish | source';

  @override
  Future<int> run() async {
    final positionals = argResults?.rest ?? const <String>[];
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'completion requires a shell name (bash | zsh | fish).',
      );
    }
    final shell = positionals.first.toLowerCase();
    // Completion scripts are the command's entire output — write
    // straight to stdout rather than pulling in a logger abstraction.
    stdout.writeln(buildCompletionScript(shell));
    return 0;
  }
}

/// Build the completion script for [shell]. Pure function so tests
/// can hit it directly. Throws [AppError] with [AppErrorCodes.invalidArgs]
/// for unsupported shells.
String buildCompletionScript(String shell) {
  // Build a fresh runner just to enumerate subcommand names — we
  // never execute it. Naming this `agent-device` (not `ad`) keeps
  // the emitted scripts stable regardless of which symlink the user
  // happened to invoke.
  final runner = buildCliRunner(executableName: 'agent-device');
  final subcommands = runner.commands.values.map((c) => c.name).toList()
    ..sort();
  return switch (shell.toLowerCase()) {
    'bash' => _bashScript(subcommands),
    'zsh' => _zshScript(subcommands),
    'fish' => _fishScript(subcommands),
    _ => throw AppError(
      AppErrorCodes.invalidArgs,
      'Unsupported shell: $shell. Choose bash, zsh, or fish.',
    ),
  };
}

const List<String> _platformValues = [
  'ios',
  'android',
  'macos',
  'linux',
  'apple',
];
const List<String> _commonFlags = [
  '--help',
  '--json',
  '--verbose',
  '--debug',
  '--platform',
  '--serial',
  '--device',
  '--session',
  '--state-dir',
  '--ephemeral-session',
];

String _bashScript(List<String> subcommands) {
  final cmdList = subcommands.join(' ');
  final flagList = _commonFlags.join(' ');
  final platformList = _platformValues.join(' ');
  return '''
# agent-device bash completion. Source via: eval "\$(agent-device completion bash)"
_agent_device_complete() {
  local cur prev words cword
  COMPREPLY=()
  cur="\${COMP_WORDS[COMP_CWORD]}"
  prev="\${COMP_WORDS[COMP_CWORD-1]}"

  # Subcommand position.
  if [[ \$COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( \$(compgen -W "$cmdList" -- "\$cur") )
    return 0
  fi

  # Value completion for known options.
  case "\$prev" in
    --platform)
      COMPREPLY=( \$(compgen -W "$platformList" -- "\$cur") )
      return 0
      ;;
    --serial|--device|--session|--state-dir)
      return 0
      ;;
  esac

  # Anything starting with `-` → flag completion.
  if [[ "\$cur" == -* ]]; then
    COMPREPLY=( \$(compgen -W "$flagList" -- "\$cur") )
    return 0
  fi

  # Default to file path completion (covers install <path>, record start <path>, etc).
  COMPREPLY=( \$(compgen -f -- "\$cur") )
  return 0
}
complete -F _agent_device_complete agent-device
complete -F _agent_device_complete ad
''';
}

String _zshScript(List<String> subcommands) {
  // zsh `_arguments` style. List subcommands as a state and dispatch
  // common flags. Keeps it minimal — full per-subcommand flag handling
  // would require enumerating every command's argParser.
  final cmdList = subcommands.map((c) => "'$c'").join(' ');
  final platformList = _platformValues.map((p) => "'$p'").join(' ');
  return '''
#compdef agent-device ad
# agent-device zsh completion. Source via: eval "\$(agent-device completion zsh)"
_agent_device() {
  local -a subcommands platforms
  subcommands=( $cmdList )
  platforms=( $platformList )

  _arguments -C \\
    '--help[Print usage]' \\
    '--json[Emit JSON output]' \\
    '--verbose[Verbose output]' \\
    '--debug[Alias for --verbose]' \\
    '--platform[Device platform]:platform:->platform' \\
    '--serial[Device serial / udid]:serial:' \\
    '--device[Device name]:device:' \\
    '--session[Session name]:session:' \\
    '--state-dir[State directory override]:dir:_files -/' \\
    '--ephemeral-session[Use in-memory session store]' \\
    '1: :->subcommand' \\
    '*::arg:_files'

  case \$state in
    subcommand)
      _values 'agent-device subcommand' \$subcommands
      ;;
    platform)
      _values 'platform' \$platforms
      ;;
  esac
}
_agent_device "\$@"
''';
}

String _fishScript(List<String> subcommands) {
  final lines = <String>[
    '# agent-device fish completion. Source via:',
    '#   agent-device completion fish | source',
    '#   # …or persist it:',
    '#   agent-device completion fish > ~/.config/fish/completions/agent-device.fish',
    '',
  ];
  // Top-level subcommands.
  for (final cmd in subcommands) {
    lines.add(
      "complete -c agent-device -f -n '__fish_use_subcommand' -a '$cmd'",
    );
    lines.add("complete -c ad -f -n '__fish_use_subcommand' -a '$cmd'");
  }
  // Common flags (no argument).
  for (final flag in const [
    '--help',
    '--json',
    '--verbose',
    '--debug',
    '--ephemeral-session',
  ]) {
    final long = flag.replaceFirst('--', '');
    lines.add('complete -c agent-device -l $long');
    lines.add('complete -c ad -l $long');
  }
  // Platform value completion.
  final platformChoices = _platformValues.join(' ');
  lines.add("complete -c agent-device -l platform -x -a '$platformChoices'");
  lines.add("complete -c ad -l platform -x -a '$platformChoices'");
  // Options that take string args (no useful value list).
  for (final opt in const ['serial', 'device', 'session']) {
    lines.add('complete -c agent-device -l $opt -x');
    lines.add('complete -c ad -l $opt -x');
  }
  // Path-y option.
  lines.add('complete -c agent-device -l state-dir -F');
  lines.add('complete -c ad -l state-dir -F');
  return lines.join('\n');
}
