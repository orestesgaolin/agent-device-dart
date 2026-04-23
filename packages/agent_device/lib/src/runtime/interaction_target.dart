// Phase 7: typed target abstraction over points, refs, and selector
// expressions. Folded into [AgentDevice] so callers can pass the same
// value to tap / fill / focus / longPress / get / is / wait.
library;

import 'package:agent_device/src/selectors/selectors.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';

/// What to interact with: an absolute point, an `@ref` label from the last
/// snapshot, or a parsed selector chain.
sealed class InteractionTarget {
  const InteractionTarget();

  /// Absolute `(x, y)` point on the current screen.
  factory InteractionTarget.xy(num x, num y) =>
      PointTarget(Point(x: x.toDouble(), y: y.toDouble()));

  /// Ref label from the current snapshot, with or without the leading `@`.
  factory InteractionTarget.ref(String ref, {String? fallbackLabel}) {
    final normalized = normalizeRef(ref);
    if (normalized == null) {
      throw ArgumentError.value(ref, 'ref', 'not a valid ref');
    }
    return RefTarget(ref: normalized, fallbackLabel: fallbackLabel);
  }

  /// Selector expression, e.g. `label=Submit && role=button` (see
  /// `parseSelectorChain`).
  factory InteractionTarget.selector(String source) =>
      SelectorTarget(chain: parseSelectorChain(source), source: source);

  /// Auto-detect the most likely shape from one raw string token:
  ///
  /// - `@e3` or `e3` (ref-ish) → [RefTarget]
  /// - Otherwise → [SelectorTarget] (parsed; throws if invalid)
  ///
  /// Coordinate pairs don't fit this single-string shape — use
  /// [InteractionTarget.parseArgs] for the CLI positional-arg case.
  factory InteractionTarget.parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(input, 'input', 'empty target');
    }
    if (trimmed.startsWith('@')) {
      return InteractionTarget.ref(trimmed);
    }
    return InteractionTarget.selector(trimmed);
  }

  /// CLI-friendly parser. Accepts:
  ///
  /// - `['x', 'y']` (two integers) → [PointTarget]
  /// - `['@e3']` → [RefTarget]
  /// - `['label=Submit', '&&', 'role=button']` or
  ///   `['label=Submit && role=button']` → [SelectorTarget]
  ///
  /// Returns null when [args] doesn't parse as any of the above.
  static InteractionTarget? parseArgs(List<String> args) {
    if (args.isEmpty) return null;
    if (args.length >= 2) {
      final x = num.tryParse(args[0]);
      final y = num.tryParse(args[1]);
      if (x != null && y != null) return InteractionTarget.xy(x, y);
    }
    final first = args.first.trim();
    if (first.startsWith('@')) return InteractionTarget.ref(first);
    // Join all tokens — the user may have typed `label=Submit && role=button`
    // as three shell words.
    final joined = args.join(' ').trim();
    final parsed = tryParseSelectorChain(joined);
    if (parsed != null) {
      return SelectorTarget(chain: parsed, source: joined);
    }
    return null;
  }
}

class PointTarget extends InteractionTarget {
  final Point point;
  const PointTarget(this.point);

  @override
  String toString() =>
      'PointTarget(${point.x.toStringAsFixed(0)}, '
      '${point.y.toStringAsFixed(0)})';
}

class RefTarget extends InteractionTarget {
  final String ref;
  final String? fallbackLabel;
  const RefTarget({required this.ref, this.fallbackLabel});

  @override
  String toString() => 'RefTarget(@$ref)';
}

class SelectorTarget extends InteractionTarget {
  final SelectorChain chain;

  /// Original user-supplied text — surfaced in error messages.
  final String source;

  const SelectorTarget({required this.chain, required this.source});

  @override
  String toString() => 'SelectorTarget($source)';
}
