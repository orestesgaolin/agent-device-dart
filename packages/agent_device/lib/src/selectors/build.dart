// Port of agent-device/src/utils/selector-build.ts
library;

import 'dart:convert';

import 'package:agent_device/src/snapshot/processing.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';

import 'selector_node.dart';

/// Build selector chain alternatives for a node.
List<String> buildSelectorChainForNode(
  SnapshotNode node,
  String platform, {
  String? action,
}) {
  final chain = <String>[];
  final role = _normalizeType(node.type ?? '');
  final id = _normalizeSelectorText(node.identifier);
  final label = _normalizeSelectorText(node.label);
  final value = _normalizeSelectorText(node.value);
  final text = _normalizeSelectorText(extractNodeText(node));
  final requireEditable = action == 'fill';

  if (id != null) {
    chain.add('id=${_quoteSelectorValue(id)}');
  }
  if (role.isNotEmpty && label != null) {
    if (requireEditable) {
      chain.add(
        'role=${_quoteSelectorValue(role)} label=${_quoteSelectorValue(label)} editable=true',
      );
    } else {
      chain.add(
        'role=${_quoteSelectorValue(role)} label=${_quoteSelectorValue(label)}',
      );
    }
  }
  if (label != null) {
    if (requireEditable) {
      chain.add('label=${_quoteSelectorValue(label)} editable=true');
    } else {
      chain.add('label=${_quoteSelectorValue(label)}');
    }
  }
  if (value != null) {
    if (requireEditable) {
      chain.add('value=${_quoteSelectorValue(value)} editable=true');
    } else {
      chain.add('value=${_quoteSelectorValue(value)}');
    }
  }
  if (text != null && text != label && text != value) {
    if (requireEditable) {
      chain.add('text=${_quoteSelectorValue(text)} editable=true');
    } else {
      chain.add('text=${_quoteSelectorValue(text)}');
    }
  }
  if (role.isNotEmpty &&
      requireEditable &&
      !chain.any((entry) => entry.contains('editable=true'))) {
    chain.add('role=${_quoteSelectorValue(role)} editable=true');
  }

  final deduped = _uniqueStrings(chain);
  if (deduped.isEmpty && role.isNotEmpty) {
    if (requireEditable) {
      deduped.add('role=${_quoteSelectorValue(role)} editable=true');
    } else {
      deduped.add('role=${_quoteSelectorValue(role)}');
    }
  }
  if (deduped.isEmpty) {
    final visible = isNodeVisible(node);
    if (visible) deduped.add('visible=true');
  }
  return deduped;
}

/// Remove duplicates from a list of strings.
List<String> _uniqueStrings(List<String> values) {
  return values.toSet().toList();
}

/// Quote a selector value as JSON.
String _quoteSelectorValue(String value) {
  return jsonEncode(value);
}

/// Normalize text for use in a selector (trim and check if meaningful).
String? _normalizeSelectorText(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

/// Normalize a type string for selector matching.
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
