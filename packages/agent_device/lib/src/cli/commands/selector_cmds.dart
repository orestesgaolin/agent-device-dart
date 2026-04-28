// Phase 7 selector/ref-aware commands: press, get, is, find, wait.
// Also provides the shared `parseTargetFromArgs` helper reused by the
// coordinate-or-selector variants of tap / fill / focus / longpress.
library;

import 'package:agent_device/src/runtime/interaction_target.dart';
import 'package:agent_device/src/selectors/selectors.dart';
import 'package:agent_device/src/utils/errors.dart';

import '../base_command.dart';

/// `press` — selector/ref-targeted tap. Takes the same positionals as
/// `tap` but accepts `@ref` or a selector expression instead of x y.
class PressCommand extends AgentDeviceCommand {
  @override
  String get name => 'press';

  @override
  String get description =>
      'Tap a node matched by a selector expression or @ref.';

  @override
  Future<int> run() async {
    final target = InteractionTarget.parseArgs(positionals);
    if (target == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'press requires <selector | @ref | x y>.',
      );
    }
    final device = await openAgentDevice();
    await device.tapTarget(target);
    emitResult({
      'pressed': _targetLabel(target),
    }, humanFormat: (_) => 'pressed ${_targetLabel(target)}');
    return 0;
  }
}

/// `click` — alias for `press`. Accepts the same selector/ref/x-y forms.
class ClickCommand extends AgentDeviceCommand {
  @override
  String get name => 'click';

  @override
  String get description =>
      'Tap a node matched by a selector expression or @ref.';

  @override
  Future<int> run() async {
    final target = InteractionTarget.parseArgs(positionals);
    if (target == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'press requires <selector | @ref | x y>.',
      );
    }
    final device = await openAgentDevice();
    await device.tapTarget(target);
    emitResult({
      'pressed': _targetLabel(target),
    }, humanFormat: (_) => 'pressed ${_targetLabel(target)}');
    return 0;
  }
}

/// `find` — search the current snapshot for nodes matching a query.
///
/// Supports three input forms (tried in priority order):
///
/// 1. **Selector DSL** — `find 'text="Yes, Tap to select"'`, `find visible`,
///    `find 'role=button selected'`. All positionals are parsed as a selector
///    expression and matched exactly.
/// 2. **Locator token** — `find text 'Yes'`, `find label 'Submit'`,
///    `find role button`. The first word specifies the field; the rest is
///    a case-insensitive substring query.
/// 3. **Plain substring** — `find 'Yes'`. Case-insensitive substring search
///    across label, value, and identifier.
class FindCommand extends AgentDeviceCommand {
  @override
  String get name => 'find';

  @override
  String get description =>
      'Find snapshot nodes by selector DSL, locator+query, or plain substring.';

  static const _locatorTokens = {'text', 'label', 'value', 'role', 'id'};

  @override
  Future<int> run() async {
    if (positionals.isEmpty) {
      throw AppError(AppErrorCodes.invalidArgs, 'find requires <query>.');
    }

    // --- Determine query mode ---
    String displayQuery;
    String locator = 'any';
    SelectorChain? selectorChain;

    // 1. Selector DSL: try to consume all positionals as a selector expression.
    final selectorSplit = splitSelectorFromArgs(positionals);
    if (selectorSplit != null && selectorSplit.rest.isEmpty) {
      selectorChain = parseSelectorChain(selectorSplit.selectorExpression);
      displayQuery = selectorSplit.selectorExpression;
    } else if (positionals.length >= 2 &&
        _locatorTokens.contains(positionals[0].toLowerCase())) {
      // 2. Locator token: first word names the field, rest is the query.
      locator = positionals[0].toLowerCase();
      displayQuery = positionals.sublist(1).join(' ');
    } else {
      // 3. Plain substring across all text fields.
      displayQuery = positionals.join(' ');
    }

    final device = await openAgentDevice();
    final hits = await device.find(
      displayQuery,
      locator: locator,
      selectorChain: selectorChain,
    );
    emitResult(
      hits,
      humanFormat: (_) {
        if (hits.isEmpty) return '(no matches for "$displayQuery")';
        final buf = StringBuffer();
        for (final h in hits) {
          final ref = h['ref'];
          final label = h['label'] ?? h['value'] ?? h['identifier'] ?? '';
          final type = h['type'] ?? '';
          buf.writeln('@$ref  $type  "$label"');
        }
        return buf.toString().trimRight();
      },
    );
    return 0;
  }
}

/// `get <attr> <target>` — read a single attribute off a node. [attr]
/// defaults to `text` if only one positional is given and it parses as a
/// target.
class GetCommand extends AgentDeviceCommand {
  @override
  String get name => 'get';

  @override
  String get description =>
      'Read a node attribute (text | label | value | identifier | type | role | rect | ref).';

  @override
  Future<int> run() async {
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'get requires [<attr>] <selector | @ref>.',
      );
    }

    // Two shapes: `get text @e3` or `get @e3` (default attr = text).
    String attr;
    List<String> rest;
    const knownAttrs = {
      'text',
      'label',
      'value',
      'identifier',
      'type',
      'role',
      'rect',
      'ref',
    };
    if (knownAttrs.contains(positionals.first)) {
      attr = positionals.first;
      rest = positionals.sublist(1);
    } else {
      attr = 'text';
      rest = positionals;
    }

    final target = InteractionTarget.parseArgs(rest);
    if (target == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'get requires a @ref or selector target.',
      );
    }

    final device = await openAgentDevice();
    final value = await device.getAttr(attr, target);
    emitResult({
      'attr': attr,
      'target': _targetLabel(target),
      'value': value,
    }, humanFormat: (_) => value?.toString() ?? '(null)');
    return 0;
  }
}

/// `is <predicate> <target>` — evaluate an `is` predicate. Exit code:
/// 0 if the predicate passed, 1 if it did not (and 1/64 for errors, as
/// usual).
class IsCommand extends AgentDeviceCommand {
  @override
  String get name => 'is';

  @override
  String get description =>
      'Check a predicate (visible | hidden | exists | editable | selected | text) '
      'on a @ref or selector. Exits 0 when true, 1 when false.';

  @override
  Future<int> run() async {
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'is requires <predicate> [args...] <selector | @ref>.',
      );
    }
    final predicate = positionals.first;
    if (!isSupportedPredicate(predicate)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Unsupported predicate: $predicate',
        details: {'predicate': predicate},
      );
    }
    // `text` predicate takes an expected value as its second positional.
    String? expectedText;
    List<String> rest;
    if (predicate == 'text' && positionals.length >= 3) {
      expectedText = positionals[1];
      rest = positionals.sublist(2);
    } else {
      rest = positionals.sublist(1);
    }
    final target = InteractionTarget.parseArgs(rest);
    if (target == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'is requires a @ref or selector target.',
      );
    }
    final device = await openAgentDevice();
    final result = await device.isPredicate(
      predicate,
      target,
      expectedText: expectedText,
    );
    emitResult(
      {
        'predicate': predicate,
        'target': _targetLabel(target),
        'pass': result.pass,
        'actualText': result.actualText,
        'details': result.details,
      },
      humanFormat: (_) => result.pass
          ? 'PASS  $predicate ${_targetLabel(target)}'
          : 'FAIL  $predicate ${_targetLabel(target)}  '
                '(actual=${result.actualText})',
    );
    return result.pass ? 0 : 1;
  }
}

/// `wait <predicate> <target> [--timeout ms] [--poll-ms ms]` — poll until
/// a predicate passes or times out.
class WaitCommand extends AgentDeviceCommand {
  WaitCommand() {
    argParser
      ..addOption('timeout', help: 'Wait timeout in ms (default: 10000).')
      ..addOption('poll-ms', help: 'Polling interval in ms (default: 400).');
  }

  @override
  String get name => 'wait';

  @override
  String get description =>
      'Poll a predicate on a @ref or selector until it passes (or times out).';

  @override
  Future<int> run() async {
    if (positionals.isEmpty) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'wait requires <predicate> [args...] <selector | @ref>.',
      );
    }
    final predicate = positionals.first;
    if (!isSupportedPredicate(predicate)) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'Unsupported predicate: $predicate',
      );
    }
    String? expectedText;
    List<String> rest;
    if (predicate == 'text' && positionals.length >= 3) {
      expectedText = positionals[1];
      rest = positionals.sublist(2);
    } else {
      rest = positionals.sublist(1);
    }
    final target = InteractionTarget.parseArgs(rest);
    if (target == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'wait requires a @ref or selector target.',
      );
    }
    final timeoutMs =
        int.tryParse(argResults?['timeout'] as String? ?? '') ?? 10000;
    final pollMs = int.tryParse(argResults?['poll-ms'] as String? ?? '') ?? 400;

    final device = await openAgentDevice();
    final result = await device.wait(
      predicate,
      target,
      timeout: Duration(milliseconds: timeoutMs),
      pollInterval: Duration(milliseconds: pollMs),
      expectedText: expectedText,
    );
    emitResult(
      {
        'predicate': predicate,
        'target': _targetLabel(target),
        'pass': result.pass,
        'actualText': result.actualText,
      },
      humanFormat: (_) => 'PASS after wait: $predicate ${_targetLabel(target)}',
    );
    return 0;
  }
}

String _targetLabel(InteractionTarget t) => switch (t) {
  PointTarget(:final point) =>
    '(${point.x.toStringAsFixed(0)}, ${point.y.toStringAsFixed(0)})',
  RefTarget(:final ref) => '@$ref',
  SelectorTarget(:final source) => source,
};
