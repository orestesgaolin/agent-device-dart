// Port of agent-device/src/platforms/ios/perf-xml.ts
//
// XML utility helpers shared between perf.dart and perf_frame.dart.
// All functions operate directly on [XmlElement] from the `xml` package —
// there is no intermediate XmlNode abstraction in the Dart port.
library;

import 'package:xml/xml.dart';

/// Recursively walk [elements] depth-first and return the first that
/// satisfies [predicate]. Returns `null` when nothing matches.
XmlElement? findFirstXmlElement(
  Iterable<XmlNode> elements,
  bool Function(XmlElement) predicate,
) {
  for (final node in elements) {
    if (node is XmlElement) {
      if (predicate(node)) return node;
      final descendant = findFirstXmlElement(node.children, predicate);
      if (descendant != null) return descendant;
    }
  }
  return null;
}

/// Recursively collect every [XmlElement] in [elements] (and their
/// descendants) that satisfies [predicate].
List<XmlElement> findAllXmlElements(
  Iterable<XmlNode> elements,
  bool Function(XmlElement) predicate,
) {
  final matches = <XmlElement>[];
  for (final node in elements) {
    if (node is XmlElement) {
      if (predicate(node)) matches.add(node);
      matches.addAll(findAllXmlElements(node.children, predicate));
    }
  }
  return matches;
}

/// Return the text content of the first child element named [childName]
/// inside [node], or `null` when absent.
String? _readFirstChildText(XmlElement node, String childName) {
  final child = node.childElements.where((c) => c.localName == childName).firstOrNull;
  return child?.innerText;
}

/// Read the ordered list of mnemonic strings from the `<schema
/// name="[schemaName]">` element found anywhere in [document].
/// Returns an empty list when the schema is not present.
List<String> readSchemaColumns(XmlDocument document, String schemaName) {
  final schema = findFirstXmlElement(
    document.children,
    (el) => el.localName == 'schema' && el.getAttribute('name') == schemaName,
  );
  if (schema == null) return const [];
  return schema.childElements
      .where((col) => col.localName == 'col')
      .map((col) => _readFirstChildText(col, 'mnemonic') ?? '')
      .toList();
}

/// Extract the numeric text value from [element], respecting `<sentinel/>`
/// cells (which collapse to `null`). Returns `null` for non-finite values
/// and when [element] is absent.
double? parseDirectXmlNumber(XmlElement? element) {
  if (element == null) return null;
  if (element.childElements.any((c) => c.localName == 'sentinel')) return null;
  final text = element.innerText.trim();
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite) return null;
  return value;
}

/// Resolve a numeric value from [element], following `ref` indirection
/// into [references] when present.
double? resolveXmlNumber(
  XmlElement? element,
  Map<String, ({double? numberValue})> references,
) {
  if (element == null) return null;
  final ref = element.getAttribute('ref');
  if (ref != null) return references[ref]?.numberValue;
  return parseDirectXmlNumber(element);
}
