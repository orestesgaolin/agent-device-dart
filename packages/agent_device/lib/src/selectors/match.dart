// Port of agent-device/src/daemon/selectors-match.ts
library;

import 'package:agent_device/src/snapshot/processing.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';

import 'parse.dart';
import 'selector_node.dart';

// Re-export node visibility helpers
export 'selector_node.dart' show isNodeVisible, isNodeEditable;

/// Check if a node matches all terms in a selector.
bool matchesSelector(SnapshotNode node, Selector selector, String platform) {
  return selector.terms.every((term) => _matchesTerm(node, term, platform));
}

/// Check if a node matches a single selector term.
bool _matchesTerm(SnapshotNode node, SelectorTerm term, String platform) {
  final key = term.key;
  final value = term.value;

  switch (key) {
    case 'id':
      return _textEquals(node.identifier, value.toString());
    case 'role':
      return _textEquals(_normalizeType(node.type ?? ''), value.toString());
    case 'label':
      return _textEquals(node.label, value.toString());
    case 'value':
      return _textEquals(node.value, value.toString());
    case 'text':
      return _textEquals(extractNodeText(node), value.toString());
    case 'appname':
      return _textEquals(node.appName, value.toString());
    case 'windowtitle':
      return _textEquals(node.windowTitle, value.toString());
    case 'visible':
      return isNodeVisible(node) == (value == true);
    case 'hidden':
      return !isNodeVisible(node) == (value == true);
    case 'editable':
      return isNodeEditable(node, platform) == (value == true);
    case 'selected':
      return (node.selected == true) == (value == true);
    case 'enabled':
      return (node.enabled != false) == (value == true);
    case 'hittable':
      return (node.hittable == true) == (value == true);
    default:
      return false;
  }
}

/// Check if two text values are equal (case-insensitive and whitespace-normalized).
bool _textEquals(String? value, String query) {
  return _normalizeText(value ?? '') == _normalizeText(query);
}

/// Normalize text for comparison (trim, lowercase, collapse whitespace).
String _normalizeText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Normalize a type string.
String _normalizeType(String type) {
  var normalized = type.toLowerCase();
  if (normalized.contains('.')) {
    final lastDot = normalized.lastIndexOf('.');
    if (lastDot != -1) {
      normalized = normalized.substring(lastDot + 1);
    }
  }
  return normalized;
}
