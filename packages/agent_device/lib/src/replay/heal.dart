// Port of agent-device/src/daemon/handlers/session-replay-heal.ts.
//
// When a selector-backed replay step fails, `healReplayAction` takes a
// fresh snapshot, extracts candidate selector expressions from the
// action (the original selector chain, or the positional selector if
// the action doesn't carry one in `result`), and tries to resolve any
// of them against the current tree. If one resolves uniquely, the
// action is rewritten with a fresh selector chain computed from the
// matched node, so the next attempt uses the current UI's shape rather
// than the stale one the script was recorded against.
library;

import 'package:agent_device/src/backend/platform.dart';
import 'package:agent_device/src/replay/script_utils.dart'
    show isClickLikeCommand;
import 'package:agent_device/src/replay/session_action.dart';
import 'package:agent_device/src/selectors/selectors.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';

/// Extract a fill-text value from a fill [action], mirroring the TS
/// `inferFillText` — tolerant of ref-prefixed, coord-prefixed, or bare
/// selector-prefixed positional layouts.
String inferFillText(SessionAction action) {
  final resultText = action.result?['text'];
  if (resultText is String && resultText.trim().isNotEmpty) {
    return resultText;
  }
  final positionals = action.positionals;
  if (positionals.isEmpty) return '';
  if (positionals[0].startsWith('@')) {
    if (positionals.length >= 3) {
      return positionals.sublist(2).join(' ').trim();
    }
    return positionals.sublist(1).join(' ').trim();
  }
  if (positionals.length >= 3 &&
      num.tryParse(positionals[0]) != null &&
      num.tryParse(positionals[1]) != null) {
    return positionals.sublist(2).join(' ').trim();
  }
  return positionals.sublist(1).join(' ').trim();
}

/// Parse the `wait <selector> [timeoutMs]` positionals. Returns the
/// selector expression and the optional trailing timeout (still as a
/// string so callers can serialize it back verbatim).
({String? selectorExpression, String? selectorTimeout})
parseSelectorWaitPositionals(List<String> positionals) {
  if (positionals.isEmpty) {
    return (selectorExpression: null, selectorTimeout: null);
  }
  final maybeTimeout = positionals.last;
  final hasTimeout = RegExp(r'^\d+$').hasMatch(maybeTimeout);
  final selectorTokens = hasTimeout
      ? positionals.sublist(0, positionals.length - 1)
      : List<String>.from(positionals);
  final split = splitSelectorFromArgs(selectorTokens);
  if (split == null || split.rest.isNotEmpty) {
    return (selectorExpression: null, selectorTimeout: null);
  }
  return (
    selectorExpression: split.selectorExpression,
    selectorTimeout: hasTimeout ? maybeTimeout : null,
  );
}

/// Collect every candidate selector expression that could be used to
/// re-resolve a failed action. Includes any previously recorded
/// `selectorChain` entries from the action's `result` metadata plus
/// reconstructions from the positional layout (e.g. the selector used
/// in a `click id=foo` invocation).
List<String> collectReplaySelectorCandidates(SessionAction action) {
  final result = <String>[];
  final recorded = action.result?['selectorChain'];
  if (recorded is List) {
    for (final entry in recorded) {
      if (entry is String) result.add(entry);
    }
  }

  if (isClickLikeCommand(action.command)) {
    final first = action.positionals.isNotEmpty ? action.positionals[0] : '';
    if (first.isNotEmpty && !first.startsWith('@')) {
      result.add(action.positionals.join(' '));
    }
  }
  if (action.command == 'fill') {
    final first = action.positionals.isNotEmpty ? action.positionals[0] : '';
    if (first.isNotEmpty &&
        !first.startsWith('@') &&
        num.tryParse(first) == null) {
      result.add(first);
    }
  }
  if (action.command == 'get') {
    final selector = action.positionals.length > 1 ? action.positionals[1] : '';
    if (selector.isNotEmpty && !selector.startsWith('@')) {
      result.add(action.positionals.sublist(1).join(' '));
    }
  }
  if (action.command == 'is') {
    final isSplit = splitIsSelectorArgs(action.positionals);
    final split = isSplit.split;
    if (split != null) {
      result.add(split.selectorExpression);
    }
  }
  if (action.command == 'wait') {
    final w = parseSelectorWaitPositionals(action.positionals);
    if (w.selectorExpression != null) {
      result.add(w.selectorExpression!);
    }
  }

  final seen = <String>{};
  return result
      .where((e) => e.trim().isNotEmpty && seen.add(e))
      .toList(growable: false);
}

/// Best-effort rewrite of [action] against [nodes] (a current snapshot).
/// Returns the healed action on success, or null if none of the
/// candidate selector chains resolved uniquely.
SessionAction? healReplayAction({
  required SessionAction action,
  required List<SnapshotNode> nodes,
  required AgentDeviceBackendPlatform platform,
}) {
  if (!(isClickLikeCommand(action.command) ||
      action.command == 'fill' ||
      action.command == 'get' ||
      action.command == 'is' ||
      action.command == 'wait')) {
    return null;
  }

  final candidates = collectReplaySelectorCandidates(action);
  if (candidates.isEmpty) return null;

  final requiresRect =
      isClickLikeCommand(action.command) || action.command == 'fill';
  final allowDisambiguation =
      isClickLikeCommand(action.command) ||
      action.command == 'fill' ||
      (action.command == 'get' &&
          action.positionals.isNotEmpty &&
          action.positionals[0] == 'text');

  for (final expression in candidates) {
    final chain = tryParseSelectorChain(expression);
    if (chain == null) continue;
    final resolved = resolveSelectorChain(
      nodes,
      chain,
      platform: platform.name,
      requireRect: requiresRect,
      requireUnique: true,
      disambiguateAmbiguous: allowDisambiguation,
    );
    if (resolved == null) continue;

    final rebuilt = buildSelectorChainForNode(
      resolved.node,
      platform.name,
      action: isClickLikeCommand(action.command)
          ? 'click'
          : action.command == 'fill'
          ? 'fill'
          : 'get',
    );
    if (rebuilt.isEmpty) continue;
    final selectorExpression = rebuilt.join(' || ');

    if (isClickLikeCommand(action.command)) {
      return action.copyWith(positionals: [selectorExpression]);
    }
    if (action.command == 'fill') {
      final text = inferFillText(action);
      if (text.isEmpty) continue;
      return action.copyWith(positionals: [selectorExpression, text]);
    }
    if (action.command == 'get') {
      final sub = action.positionals.isNotEmpty ? action.positionals[0] : '';
      if (sub != 'text' && sub != 'attrs') continue;
      return action.copyWith(positionals: [sub, selectorExpression]);
    }
    if (action.command == 'is') {
      final isSplit = splitIsSelectorArgs(action.positionals);
      final predicate = isSplit.predicate;
      if (predicate.isEmpty) continue;
      final expectedText = isSplit.split?.rest.join(' ').trim() ?? '';
      final next = <String>[predicate, selectorExpression];
      if (predicate == 'text' && expectedText.isNotEmpty) {
        next.add(expectedText);
      }
      return action.copyWith(positionals: next);
    }
    if (action.command == 'wait') {
      final w = parseSelectorWaitPositionals(action.positionals);
      final next = <String>[selectorExpression];
      if (w.selectorTimeout != null) next.add(w.selectorTimeout!);
      return action.copyWith(positionals: next);
    }
  }
  return null;
}
