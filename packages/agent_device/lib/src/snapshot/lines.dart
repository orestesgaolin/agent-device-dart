// Port of agent-device/src/utils/snapshot-lines.ts
library;

import 'snapshot.dart';

// ===== Text Surface Utilities (from text-surface.ts) =====

/// Trim text value if it's a string.
String _trimText(Object? value) {
  return value is String ? value.trim() : '';
}

/// Normalize a type string for comparison.
String _normalizeType(String type) {
  var normalized = type
      .trim()
      .replaceAll(RegExp('XCUIElementType', caseSensitive: false), '')
      .replaceAll(RegExp('^AX', caseSensitive: false), '')
      .toLowerCase();
  final lastSeparator = [
    normalized.lastIndexOf('.'),
    normalized.lastIndexOf('/'),
  ].reduce((a, b) => a > b ? a : b);
  if (lastSeparator != -1) {
    normalized = normalized.substring(lastSeparator + 1);
  }
  return normalized;
}

/// Check if type prefers value for readable text.
bool _prefersValueForReadableText(String type) {
  final normalized = _normalizeType(type);
  return normalized.contains('textfield') ||
      normalized.contains('securetextfield') ||
      normalized.contains('searchfield') ||
      normalized.contains('edittext') ||
      normalized.contains('textview') ||
      normalized.contains('textarea');
}

/// Check if a value is a meaningful readable identifier.
bool _isMeaningfulReadableIdentifier(String value) {
  if (value.isEmpty) return false;
  return !RegExp(
        r'^[\w.]+:id\/[\w.-]+$',
        caseSensitive: false,
      ).hasMatch(value) &&
      !RegExp(r'^_?NS:\d+$', caseSensitive: false).hasMatch(value);
}

/// Extract readable text from a node.
String _extractReadableText(SnapshotNode node) {
  final label = _trimText(node.label);
  final value = _trimText(node.value);
  final identifier = _trimText(node.identifier);
  final fallbackIdentifier = _isMeaningfulReadableIdentifier(identifier)
      ? identifier
      : '';
  if (_prefersValueForReadableText(node.type ?? '')) {
    return value.isNotEmpty
        ? value
        : (label.isNotEmpty ? label : fallbackIdentifier);
  }
  return label.isNotEmpty
      ? label
      : (value.isNotEmpty ? value : fallbackIdentifier);
}

/// Check if a node is a large text surface.
bool _isLargeTextSurface(SnapshotNode node, String? displayType) {
  if (displayType == 'text-view' ||
      displayType == 'text-field' ||
      displayType == 'search') {
    return true;
  }
  final normalized = _normalizeType(node.type ?? '');
  final rawRole = '${node.role ?? ''} ${node.subrole ?? ''}'.toLowerCase();
  return normalized.contains('textview') ||
      normalized.contains('textarea') ||
      normalized.contains('textfield') ||
      normalized.contains('securetextfield') ||
      normalized.contains('searchfield') ||
      normalized.contains('edittext') ||
      rawRole.contains('text area') ||
      rawRole.contains('text field');
}

/// Check if text surface should be summarized.
bool _shouldSummarizeTextSurface(String text) {
  if (text.isEmpty) return false;
  return text.length > 80 || RegExp(r'[\r\n]').hasMatch(text);
}

/// Build a preview of text (truncated).
String _buildTextPreview(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 48) {
    return normalized;
  }
  return '${normalized.substring(0, 45)}...';
}

/// Describe a text surface in a node.
({String text, bool isLargeSurface, bool shouldSummarize}) _describeTextSurface(
  SnapshotNode node,
  String? displayType,
) {
  final text = _extractReadableText(node);
  final isLargeSurface = _isLargeTextSurface(node, displayType);
  return (
    text: text,
    isLargeSurface: isLargeSurface,
    shouldSummarize: isLargeSurface && _shouldSummarizeTextSurface(text),
  );
}

// ===== Scroll Indicator Utilities (from scroll-indicator.ts) =====

/// Check if a label looks like a system scroll indicator.
bool _isSystemScrollIndicatorLabel(String label) {
  final normalized = label.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return RegExp(
    r'^(vertical|horizontal)\s+scroll\s+bar(?:,?\s*\d+\s+pages?)?$',
  ).hasMatch(normalized);
}

// ===== Snapshot Lines =====

/// A line in the snapshot display (internal).
class _SnapshotDisplayLineInternal {
  final SnapshotNode node;
  final int depth;
  final String type;
  final String text;

  _SnapshotDisplayLineInternal({
    required this.node,
    required this.depth,
    required this.type,
    required this.text,
  });
}

/// Options for formatting snapshot lines.
class SnapshotLineFormatOptions {
  final bool summarizeTextSurfaces;

  const SnapshotLineFormatOptions({this.summarizeTextSurfaces = false});
}

/// Build display lines from snapshot nodes.
List<_SnapshotDisplayLineInternal> _buildSnapshotDisplayLines(
  List<SnapshotNode> nodes, [
  SnapshotLineFormatOptions? options,
]) {
  options ??= const SnapshotLineFormatOptions();
  final visibleDepths = <int>[];
  final lines = <_SnapshotDisplayLineInternal>[];

  for (final node in nodes) {
    final depth = node.depth ?? 0;
    final label = _trimText(node.label);
    final value = _trimText(node.value);
    final identifier = _trimText(node.identifier);
    final displayLabel = label.isNotEmpty
        ? label
        : (value.isNotEmpty
              ? value
              : (identifier.isNotEmpty ? identifier : ''));
    final type = _formatRole(node.type ?? 'Element');

    if (type == 'group' && displayLabel.isEmpty) {
      continue;
    }

    while (visibleDepths.isNotEmpty && depth <= visibleDepths.last) {
      visibleDepths.removeLast();
    }

    final adjustedDepth = visibleDepths.length;
    visibleDepths.add(depth);

    lines.add(
      _SnapshotDisplayLineInternal(
        node: node,
        depth: adjustedDepth,
        type: type,
        text: _formatSnapshotLine(node, adjustedDepth, false, type, options),
      ),
    );
  }

  return lines;
}

/// Format a single snapshot line.
String _formatSnapshotLine(
  SnapshotNode node,
  int depth,
  bool hiddenGroup,
  String? normalizedType,
  SnapshotLineFormatOptions options,
) {
  final type = normalizedType ?? _formatRole(node.type ?? 'Element');
  final textSurface = _describeTextSurface(node, type);
  final label = _resolveDisplayLabel(node, type, options, textSurface);
  final indent = '  ' * depth;
  final ref = node.ref.isNotEmpty ? '@${node.ref}' : '';
  final metadata = _buildLineMetadata(node, type, options, textSurface);
  final metadataText = metadata.map((entry) => ' [$entry]').join('');
  final textPart = label.isNotEmpty ? ' "$label"' : '';

  if (hiddenGroup) {
    return '$indent$ref [$type]$metadataText'.trimRight();
  }
  return '$indent$ref [$type]$textPart$metadataText'.trimRight();
}

/// Format role/type as a display label.
String _formatRole(String type) {
  var normalized = type
      .replaceAll(RegExp('XCUIElementType', caseSensitive: false), '')
      .toLowerCase();
  final isAndroidClass =
      type.contains('.') &&
      (type.startsWith('android.') ||
          type.startsWith('androidx.') ||
          type.startsWith('com.'));

  if (normalized.contains('.')) {
    normalized = normalized
        .replaceAll(RegExp('^android\\.widget\\.'), '')
        .replaceAll(RegExp('^android\\.view\\.'), '')
        .replaceAll(RegExp('^android\\.webkit\\.'), '')
        .replaceAll(RegExp('^androidx\\.'), '')
        .replaceAll(RegExp('^com\\.google\\.android\\.'), '')
        .replaceAll(RegExp('^com\\.android\\.'), '');

    if (isAndroidClass && normalized.contains('.')) {
      normalized = normalized.substring(normalized.lastIndexOf('.') + 1);
    }
  }

  switch (normalized) {
    case 'application':
      return 'application';
    case 'navigationbar':
      return 'navigation-bar';
    case 'tabbar':
      return 'tab-bar';
    case 'button' || 'imagebutton':
      return 'button';
    case 'link':
      return 'link';
    case 'cell':
      return 'cell';
    case 'statictext' || 'checkedtextview':
      return 'text';
    case 'textfield' || 'edittext':
      return 'text-field';
    case 'textview':
      return isAndroidClass ? 'text' : 'text-view';
    case 'textarea':
      return 'text-view';
    case 'switch':
      return 'switch';
    case 'slider':
      return 'slider';
    case 'image' || 'imageview':
      return 'image';
    case 'webview':
      return 'webview';
    case 'framelayout' ||
        'linearlayout' ||
        'relativelayout' ||
        'constraintlayout' ||
        'viewgroup' ||
        'view':
      return 'group';
    case 'listview' || 'recyclerview':
      return 'list';
    case 'collectionview':
      return 'collection';
    case 'searchfield':
      return 'search';
    case 'segmentedcontrol':
      return 'segmented-control';
    case 'group':
      return 'group';
    case 'window':
      return 'window';
    case 'checkbox':
      return 'checkbox';
    case 'radio':
      return 'radio';
    case 'menuitem':
      return 'menu-item';
    case 'toolbar':
      return 'toolbar';
    case 'scrollarea' || 'scrollview' || 'nestedscrollview':
      return 'scroll-area';
    case 'table':
      return 'table';
    default:
      return normalized.isEmpty ? 'element' : normalized;
  }
}

/// Check if a type is editable.
bool _isEditableRole(String type) {
  return type == 'text-field' || type == 'text-view' || type == 'search';
}

/// Check if a scroll container label should be suppressed.
bool _shouldSuppressScrollContainerLabel(String type, String label) {
  if (type != 'scroll-area' &&
      type != 'list' &&
      type != 'collection' &&
      type != 'table') {
    return false;
  }
  return _isSystemScrollIndicatorLabel(label);
}

/// Check if a value is a generic resource ID.
bool _isGenericResourceId(String value) {
  return RegExp(r'^[\w.]+:id\/[\w.-]+$', caseSensitive: false).hasMatch(value);
}

/// Display label for a node (respects role-based suppression).
String _displayLabel(SnapshotNode node, String type) {
  final label = _trimText(node.label);
  if (label.isNotEmpty && _shouldSuppressScrollContainerLabel(type, label)) {
    return '';
  }
  if (label.isNotEmpty) {
    if (_isEditableRole(type)) {
      final value = _trimText(node.value);
      if (value.isNotEmpty) return value;
      return label;
    }
    return label;
  }
  final value = _trimText(node.value);
  if (value.isNotEmpty) return value;

  final identifier = _trimText(node.identifier);
  if (identifier.isEmpty) return '';
  if (_isGenericResourceId(identifier) &&
      (type == 'group' ||
          type == 'image' ||
          type == 'list' ||
          type == 'collection')) {
    return '';
  }
  return identifier;
}

/// Resolve display label with optional text surface summarization.
String _resolveDisplayLabel(
  SnapshotNode node,
  String type,
  SnapshotLineFormatOptions options,
  ({String text, bool isLargeSurface, bool shouldSummarize}) textSurface,
) {
  if (!options.summarizeTextSurfaces) {
    return _displayLabel(node, type);
  }
  if (!textSurface.shouldSummarize) {
    return _displayLabel(node, type);
  }

  final semanticLabel = _semanticSurfaceLabel(node, type, textSurface.text);
  return semanticLabel.isNotEmpty ? semanticLabel : _displayLabel(node, type);
}

/// Semantic label for a text surface.
String _semanticSurfaceLabel(SnapshotNode node, String type, String text) {
  final label = _trimText(node.label);
  if (label.isNotEmpty && label != text) {
    return label;
  }
  final identifier = _trimText(node.identifier);
  if (identifier.isNotEmpty &&
      !_isGenericResourceId(identifier) &&
      identifier != text) {
    return identifier;
  }

  switch (type) {
    case 'text' || 'text-view':
      return 'Text view';
    case 'text-field':
      return 'Text field';
    case 'search':
      return 'Search field';
    default:
      return '';
  }
}

/// Check if a node looks scrollable.
bool _looksScrollable(SnapshotNode node, String type) {
  if (type == 'scroll-area') return true;
  final rawType = (node.type ?? '').toLowerCase();
  final rawRole = '${node.role ?? ''} ${node.subrole ?? ''}'.toLowerCase();
  return rawType.contains('scroll') || rawRole.contains('scroll');
}

/// Escape special characters in preview text.
String _escapePreviewText(String value) {
  return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}

/// Remove duplicates while preserving order.
List<String> _uniqueMetadata(List<String> values) {
  final seen = <String>{};
  return values.where((v) => seen.add(v)).toList();
}

/// Build metadata entries for a line.
List<String> _buildLineMetadata(
  SnapshotNode node,
  String type,
  SnapshotLineFormatOptions options,
  ({String text, bool isLargeSurface, bool shouldSummarize}) textSurface,
) {
  final metadata = <String>[];
  if (node.enabled == false) metadata.add('disabled');
  if (!options.summarizeTextSurfaces) {
    return metadata;
  }
  if (node.selected == true) metadata.add('selected');
  if (_isEditableRole(type)) metadata.add('editable');
  if (_looksScrollable(node, type)) metadata.add('scrollable');
  if (!textSurface.shouldSummarize) {
    return metadata;
  }
  metadata.add(
    'preview:"${_escapePreviewText(_buildTextPreview(textSurface.text))}"',
  );
  metadata.add('truncated');
  return _uniqueMetadata(metadata);
}

/// A line in the snapshot display.
class SnapshotDisplayLine {
  final SnapshotNode node;
  final int depth;
  final String type;
  final String text;

  SnapshotDisplayLine({
    required this.node,
    required this.depth,
    required this.type,
    required this.text,
  });
}

/// Build snapshot display lines (public API).
List<SnapshotDisplayLine> buildSnapshotDisplayLinesPublic(
  List<SnapshotNode> nodes, [
  SnapshotLineFormatOptions? options,
]) {
  final lines = _buildSnapshotDisplayLines(nodes, options);
  return lines
      .map(
        (line) => SnapshotDisplayLine(
          node: line.node,
          depth: line.depth,
          type: line.type,
          text: line.text,
        ),
      )
      .toList();
}

/// Format a snapshot line (public API).
String formatSnapshotLine(
  SnapshotNode node,
  int depth,
  bool hiddenGroup,
  String? normalizedType,
  SnapshotLineFormatOptions? options,
) {
  options ??= const SnapshotLineFormatOptions();
  return _formatSnapshotLine(node, depth, hiddenGroup, normalizedType, options);
}

/// Display label for a node (public API).
String displayLabel(SnapshotNode node, String type) {
  return _displayLabel(node, type);
}

/// Format role/type (public API).
String formatRole(String type) {
  return _formatRole(type);
}
