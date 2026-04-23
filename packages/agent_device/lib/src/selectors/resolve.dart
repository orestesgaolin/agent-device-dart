// Port of agent-device/src/daemon/selectors-resolve.ts
library;

import 'package:agent_device/src/snapshot/snapshot.dart';
import 'match.dart';
import 'parse.dart';

/// Diagnostic information about a selector match.
class SelectorDiagnostics {
  final String selector;
  final int matches;

  const SelectorDiagnostics({required this.selector, required this.matches});
}

/// Result of resolving a selector chain to a single node.
class SelectorResolution {
  final SnapshotNode node;
  final Selector selector;
  final int selectorIndex;
  final int matches;
  final List<SelectorDiagnostics> diagnostics;

  const SelectorResolution({
    required this.node,
    required this.selector,
    required this.selectorIndex,
    required this.matches,
    required this.diagnostics,
  });
}

/// Resolve a selector chain to a single node with options.
SelectorResolution? resolveSelectorChain(
  List<SnapshotNode> nodes,
  SelectorChain chain, {
  required String platform,
  bool requireRect = false,
  bool requireUnique = true,
  bool disambiguateAmbiguous = false,
}) {
  final diagnostics = <SelectorDiagnostics>[];
  for (var i = 0; i < chain.selectors.length; i += 1) {
    final selector = chain.selectors[i];
    final summary = _analyzeSelectorMatches(
      nodes,
      selector,
      platform,
      requireRect,
    );
    diagnostics.add(
      SelectorDiagnostics(selector: selector.raw, matches: summary.count),
    );
    if (summary.count == 0 || summary.firstNode == null) continue;
    if (requireUnique && summary.count != 1) {
      if (!disambiguateAmbiguous || summary.disambiguated == null) continue;
      return SelectorResolution(
        node: summary.disambiguated!,
        selector: selector,
        selectorIndex: i,
        matches: summary.count,
        diagnostics: diagnostics,
      );
    }
    return SelectorResolution(
      node: summary.firstNode!,
      selector: selector,
      selectorIndex: i,
      matches: summary.count,
      diagnostics: diagnostics,
    );
  }
  return null;
}

/// Find the first matching selector in a chain (without uniqueness requirement).
({
  int selectorIndex,
  Selector selector,
  int matches,
  List<SelectorDiagnostics> diagnostics,
})?
findSelectorChainMatch(
  List<SnapshotNode> nodes,
  SelectorChain chain, {
  required String platform,
  bool requireRect = false,
}) {
  final diagnostics = <SelectorDiagnostics>[];
  for (var i = 0; i < chain.selectors.length; i += 1) {
    final selector = chain.selectors[i];
    final matches = _countSelectorMatchesOnly(
      nodes,
      selector,
      platform,
      requireRect,
    );
    diagnostics.add(
      SelectorDiagnostics(selector: selector.raw, matches: matches),
    );
    if (matches > 0) {
      return (
        selectorIndex: i,
        selector: selector,
        matches: matches,
        diagnostics: diagnostics,
      );
    }
  }
  return null;
}

/// Format a failure message for selector resolution.
String formatSelectorFailure(
  SelectorChain chain,
  List<SelectorDiagnostics> diagnostics, {
  bool unique = true,
}) {
  if (diagnostics.isEmpty) {
    return 'Selector did not match: ${chain.raw}';
  }
  final summary = diagnostics
      .map((e) => '${e.selector} -> ${e.matches}')
      .join(', ');
  return unique
      ? 'Selector did not resolve uniquely ($summary)'
      : 'Selector did not match ($summary)';
}

/// Analyze selector matches and find best disambiguation candidate.
({int count, SnapshotNode? firstNode, SnapshotNode? disambiguated})
_analyzeSelectorMatches(
  List<SnapshotNode> nodes,
  Selector selector,
  String platform,
  bool requireRect,
) {
  var count = 0;
  SnapshotNode? firstNode;
  SnapshotNode? best;
  var tie = false;

  for (final node in nodes) {
    if (requireRect && node.rect == null) continue;
    if (!matchesSelector(node, selector, platform)) continue;
    count += 1;
    firstNode ??= node;
    if (best == null) {
      best = node;
      continue;
    }
    final comparison = _compareDisambiguationCandidates(node, best);
    if (comparison > 0) {
      best = node;
      tie = false;
    } else if (comparison == 0) {
      tie = true;
    }
  }

  return (count: count, firstNode: firstNode, disambiguated: tie ? null : best);
}

/// Count selector matches without returning the nodes.
int _countSelectorMatchesOnly(
  List<SnapshotNode> nodes,
  Selector selector,
  String platform,
  bool requireRect,
) {
  var count = 0;
  for (final node in nodes) {
    if (requireRect && node.rect == null) continue;
    if (!matchesSelector(node, selector, platform)) continue;
    count += 1;
  }
  return count;
}

/// Compare two nodes for disambiguation (deeper/smaller is better).
int _compareDisambiguationCandidates(SnapshotNode a, SnapshotNode b) {
  final depthA = a.depth ?? 0;
  final depthB = b.depth ?? 0;
  if (depthA != depthB) return depthA > depthB ? 1 : -1;
  final areaA = _areaOfNode(a);
  final areaB = _areaOfNode(b);
  if (areaA != areaB) return areaA < areaB ? 1 : -1;
  return 0;
}

/// Calculate the area of a node.
double _areaOfNode(SnapshotNode node) {
  if (node.rect == null) return double.infinity;
  return node.rect!.width * node.rect!.height;
}
