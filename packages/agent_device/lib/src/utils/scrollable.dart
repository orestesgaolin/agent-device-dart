// Port of agent-device/src/utils/scrollable.ts

/// Check if a type name indicates a scrollable container.
///
/// Detects common scrollable widget types across Android (ScrollView,
/// RecyclerView, ListView, GridView) and other platforms.
bool isScrollableType(String? type) {
  final value = (type ?? '').toLowerCase();
  return value.contains('scroll') ||
      value.contains('recyclerview') ||
      value.contains('listview') ||
      value.contains('gridview') ||
      value.contains('collectionview') ||
      value == 'table';
}

/// Check if a node with type/role/subrole indicates scrollability.
///
/// Extends [isScrollableType] to also consider accessibility roles.
bool isScrollableNodeLike({String? type, String? role, String? subrole}) {
  if (isScrollableType(type)) {
    return true;
  }
  final roleText = '${role ?? ''} ${subrole ?? ''}'.toLowerCase();
  return roleText.contains('scroll');
}
