import 'dart:convert';
import 'dart:io';

import 'package:agent_device/agent_device.dart';
import 'package:agent_device/src/runtime/interaction_target.dart';
import 'package:agent_device/src/snapshot/processing.dart';
import 'package:test/test.dart';

const defaultIosFixtureBundleId = 'com.example.agentDeviceFixtureApp';
const defaultAndroidFixturePackage = 'com.example.agent_device_fixture_app';

InteractionTarget _idTarget(String id) {
  return InteractionTarget.selector('id=${jsonEncode(id)}');
}

Future<String> detectBootedIosSimulatorUdid() async {
  final probe = await Process.run('xcrun', [
    'simctl',
    'list',
    'devices',
    'booted',
    '-j',
  ]);
  if (probe.exitCode != 0) {
    throw TestFailure('xcrun simctl failed: ${probe.stderr}');
  }

  final decoded = jsonDecode(probe.stdout.toString()) as Map<String, Object?>;
  final devicesByRuntime = (decoded['devices'] as Map?) ?? const {};
  for (final runtimeDevices in devicesByRuntime.values) {
    if (runtimeDevices is! List) {
      continue;
    }
    for (final device in runtimeDevices) {
      if (device is! Map) {
        continue;
      }
      if (device['state'] == 'Booted' && device['udid'] is String) {
        return device['udid'] as String;
      }
    }
  }

  throw TestFailure('No booted iOS simulator found.');
}

Future<void> relaunchFixtureApp(
  AgentDevice device,
  String appId, {
  Duration settle = const Duration(seconds: 2),
}) async {
  try {
    await device.closeApp(appId);
  } catch (_) {
    // Ignore best-effort close failures when the app is not yet running.
  }
  await device.openApp(appId);
  await Future<void>.delayed(settle);
}

Future<List<Map<String, Object?>>> waitForText(
  AgentDevice device,
  String text, {
  Duration timeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 400),
}) async {
  final deadline = DateTime.now().add(timeout);
  var lastHits = const <Map<String, Object?>>[];

  while (DateTime.now().isBefore(deadline)) {
    lastHits = await device.find(text);
    if (lastHits.isNotEmpty) {
      return lastHits;
    }
    await Future<void>.delayed(pollInterval);
  }

  final snapshot = await device.snapshot();
  final nodes = (snapshot.nodes ?? const []).whereType<SnapshotNode>().toList();
  final visible = nodes
      .map(nodeSummary)
      .where((summary) => summary.isNotEmpty)
      .take(12)
      .join(', ');
  throw TestFailure(
    'Timed out waiting for text "$text". '
    'visibleNodes=${nodes.length} sample=[$visible]',
  );
}

Future<void> expectVisibleText(
  AgentDevice device,
  String text, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final hits = await waitForText(device, text, timeout: timeout);
  expect(hits, isNotEmpty, reason: 'Expected to find "$text" in the UI.');
}

Future<void> expectNoVisibleText(
  AgentDevice device,
  String text, {
  Duration timeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 400),
}) async {
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    final hits = await device.find(text);
    if (hits.isEmpty) {
      return;
    }
    await Future<void>.delayed(pollInterval);
  }

  final remainingHits = await device.find(text);
  throw TestFailure(
    'Expected "$text" to disappear, but it remained visible '
    'with ${remainingHits.length} matches.',
  );
}

Future<void> expectVisibleId(
  AgentDevice device,
  String id, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  await device.wait('exists', _idTarget(id), timeout: timeout);
}

Future<void> expectHiddenId(
  AgentDevice device,
  String id, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  await device.wait('hidden', _idTarget(id), timeout: timeout);
}

Future<void> expectIdText(
  AgentDevice device,
  String id,
  String expectedText, {
  Duration timeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 400),
}) async {
  final deadline = DateTime.now().add(timeout);
  final expectedNormalized = _normalizeObservedText(expectedText);
  Object? lastValue;

  while (DateTime.now().isBefore(deadline)) {
    final snapshot = await device.snapshot();
    final nodes = (snapshot.nodes ?? const [])
        .whereType<SnapshotNode>()
        .where((node) => node.identifier == id)
        .toList();
    final observedValues = {
      for (final node in nodes) ..._nodeTextCandidates(node),
    }.toList();
    final normalizedObserved = observedValues
        .map(_normalizeObservedText)
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalizedObserved.contains(expectedNormalized)) {
      return;
    }
    lastValue = observedValues.isEmpty ? null : observedValues.join(' | ');
    await Future<void>.delayed(pollInterval);
  }

  throw TestFailure(
    'Timed out waiting for id "$id" text "$expectedText". '
    'lastValue=$lastValue',
  );
}

Iterable<String> _nodeTextCandidates(SnapshotNode node) sync* {
  for (final candidate in [node.label, node.value]) {
    final text = candidate?.trim();
    if (text != null && text.isNotEmpty) {
      yield text;
    }
  }
}

String _normalizeObservedText(String value) {
  final collapsed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) {
    return '';
  }

  final commaSegments = collapsed
      .split(',')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (commaSegments.length > 1) {
    final first = commaSegments.first.toLowerCase();
    final allSame = commaSegments.every(
      (segment) => segment.toLowerCase() == first,
    );
    if (allSame) {
      return first;
    }
  }

  return collapsed.toLowerCase();
}

Future<void> tapId(
  AgentDevice device,
  String id, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  await expectVisibleId(device, id, timeout: timeout);
  try {
    await device.tapTarget(
      InteractionTarget.selector(
        'id=${jsonEncode(id)} hittable=true enabled=true || '
        'id=${jsonEncode(id)} hittable=true || '
        'id=${jsonEncode(id)} enabled=true || '
        'id=${jsonEncode(id)}',
      ),
    );
  } catch (_) {
    await _tapBestTextMatch(device, id);
  }
}

Future<void> typeIntoFieldById(
  AgentDevice device,
  String id,
  String value, {
  Duration timeout = const Duration(seconds: 10),
  int? delayMs,
}) async {
  await expectVisibleId(device, id, timeout: timeout);
  await device.tapTarget(
    InteractionTarget.selector(
      'id=${jsonEncode(id)} editable=true hittable=true || '
      'id=${jsonEncode(id)} editable=true || '
      'id=${jsonEncode(id)}',
    ),
  );
  await device.typeText(value, delayMs: delayMs);
}

Future<void> fillTextFieldById(
  AgentDevice device,
  String id,
  String value, {
  Duration timeout = const Duration(seconds: 10),
  int? delayMs,
}) async {
  await expectVisibleId(device, id, timeout: timeout);
  await device.fillTarget(
    InteractionTarget.selector(
      'id=${jsonEncode(id)} editable=true hittable=true || '
      'id=${jsonEncode(id)} editable=true || '
      'id=${jsonEncode(id)}',
    ),
    value,
    delayMs: delayMs,
  );
}

Future<void> tapText(
  AgentDevice device,
  String text, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final hits = await waitForText(device, text, timeout: timeout);
  final center = rectCenterFromHit(_bestTapHit(hits), text);
  await device.tap(center.$1, center.$2);
}

Future<void> tapNearestTextRegion(
  AgentDevice device,
  String text, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final hits = await waitForText(device, text, timeout: timeout);
  try {
    final center = rectCenterFromHit(_bestTapHit(hits), text);
    await device.tap(center.$1, center.$2);
    return;
  } catch (_) {
    await _tapBestTextMatch(device, text);
  }
}

Future<void> tapButton(
  AgentDevice device,
  String label, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  await expectVisibleText(device, label, timeout: timeout);
  try {
    await device.tapTarget(
      InteractionTarget.selector(
        'label="$label" hittable=true enabled=true || '
        'label="$label" hittable=true || '
        'label="$label" enabled=true || '
        'label="$label"',
      ),
    );
  } catch (_) {
    await _tapBestTextMatch(device, label);
  }
}

Future<void> typeIntoField(
  AgentDevice device,
  String label,
  String value, {
  Duration timeout = const Duration(seconds: 10),
  int? delayMs,
}) async {
  await expectVisibleText(device, label, timeout: timeout);
  await device.tapTarget(
    InteractionTarget.selector(
      'label="$label" editable=true hittable=true || '
      'label="$label" editable=true',
    ),
  );
  await device.typeText(value, delayMs: delayMs);
}

Future<void> swipeUp(
  AgentDevice device, {
  num startX = 200,
  num startY = 640,
  num endX = 200,
  num endY = 220,
  int durationMs = 250,
}) async {
  await device.swipe(startX, startY, endX, endY, durationMs: durationMs);
}

Future<void> fillTextField(
  AgentDevice device,
  String label,
  String value, {
  Duration timeout = const Duration(seconds: 10),
  int? delayMs,
}) async {
  final hits = await waitForText(device, label, timeout: timeout);
  final center = rectCenterFromHit(hits.first, label);
  await device.fill(center.$1, center.$2, value, delayMs: delayMs);
}

(num, num) rectCenterFromHit(Map<String, Object?> hit, String label) {
  final rawRect = hit['rect'];
  if (rawRect is! Map) {
    throw TestFailure('Match for "$label" did not include rect metadata.');
  }

  final x = _readRectNumber(rawRect['x'], 'x', label);
  final y = _readRectNumber(rawRect['y'], 'y', label);
  final width = _readRectNumber(rawRect['width'], 'width', label);
  final height = _readRectNumber(rawRect['height'], 'height', label);
  return (x + (width / 2), y + (height / 2));
}

num _readRectNumber(Object? value, String key, String label) {
  if (value is num) {
    return value;
  }
  throw TestFailure('Match for "$label" had invalid rect.$key value: $value');
}

Map<String, Object?> _bestTapHit(List<Map<String, Object?>> hits) {
  return hits.reduce((best, candidate) {
    if (_preferHitForTap(candidate, best)) {
      return candidate;
    }
    return best;
  });
}

bool _preferHitForTap(
  Map<String, Object?> candidate,
  Map<String, Object?> current,
) {
  final candidateInteractive = _isInteractiveHit(candidate);
  final currentInteractive = _isInteractiveHit(current);
  if (candidateInteractive != currentInteractive) {
    return candidateInteractive;
  }

  final candidateArea = _hitRectArea(candidate);
  final currentArea = _hitRectArea(current);
  if (candidateArea != currentArea) {
    return candidateArea < currentArea;
  }

  return false;
}

bool _isInteractiveHit(Map<String, Object?> hit) {
  final type = (hit['type'] as String?)?.toLowerCase() ?? '';
  return type == 'button' ||
      type == 'checkbox' ||
      type == 'switch' ||
      type == 'textfield';
}

double _hitRectArea(Map<String, Object?> hit) {
  final rawRect = hit['rect'];
  if (rawRect is! Map) {
    return double.infinity;
  }

  final width = rawRect['width'];
  final height = rawRect['height'];
  if (width is! num || height is! num) {
    return double.infinity;
  }

  return (width * height).toDouble();
}

String nodeSummary(SnapshotNode node) {
  final text = [node.label, node.value, node.identifier]
      .whereType<String>()
      .map((value) => value.trim())
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  if (text.isEmpty) {
    return node.type ?? '';
  }
  return '${node.type ?? 'node'}:$text';
}

Future<void> _tapBestTextMatch(AgentDevice device, String text) async {
  final snapshot = await device.snapshot();
  final nodes = (snapshot.nodes ?? const []).whereType<SnapshotNode>().toList();
  final query = _normalizeSelectorText(text);

  SnapshotNode? bestHittableNode;
  SnapshotNode? bestAncestorNode;
  SnapshotNode? bestDirectNode;
  for (final node in nodes) {
    if (_normalizeSelectorText(extractNodeText(node)) != query &&
        _normalizeSelectorText(node.label) != query &&
        _normalizeSelectorText(node.value) != query &&
        _normalizeSelectorText(node.identifier) != query) {
      continue;
    }

    if (node.rect != null &&
        (bestDirectNode == null || _preferCandidate(node, bestDirectNode))) {
      bestDirectNode = node;
    }

    final candidate = findNearestHittableAncestor(nodes, node);
    if (candidate == null || candidate.rect == null) {
      final ancestor = _findNearestAncestorWithRect(nodes, node);
      if (ancestor != null &&
          (bestAncestorNode == null ||
              _preferCandidate(ancestor, bestAncestorNode))) {
        bestAncestorNode = ancestor;
      }
      continue;
    }

    if (bestHittableNode == null ||
        _preferCandidate(candidate, bestHittableNode)) {
      bestHittableNode = candidate;
    }
  }

  final target = bestHittableNode ?? bestAncestorNode ?? bestDirectNode;
  if (target == null || target.rect == null) {
    throw TestFailure('Could not find a hittable target for "$text".');
  }

  final rect = target.rect!;
  await device.tap(rect.x + (rect.width / 2), rect.y + (rect.height / 2));
}

SnapshotNode? _findNearestAncestorWithRect(
  List<SnapshotNode> nodes,
  SnapshotNode node,
) {
  var current = node;
  final visited = <String>{};

  while (current.parentIndex != null) {
    if (visited.contains(current.ref)) {
      break;
    }
    visited.add(current.ref);

    try {
      final parent = nodes.firstWhere(
        (candidate) => candidate.index == current.parentIndex,
      );
      if (parent.rect != null) {
        return parent;
      }
      current = parent;
    } on StateError {
      break;
    }
  }

  return null;
}

bool _preferCandidate(SnapshotNode candidate, SnapshotNode current) {
  final candidateDepth = candidate.depth ?? 0;
  final currentDepth = current.depth ?? 0;
  if (candidateDepth != currentDepth) {
    return candidateDepth > currentDepth;
  }

  final candidateArea = _rectArea(candidate.rect);
  final currentArea = _rectArea(current.rect);
  return candidateArea < currentArea;
}

double _rectArea(Rect? rect) {
  if (rect == null) {
    return double.infinity;
  }
  return rect.width * rect.height;
}

String _normalizeSelectorText(String? value) {
  if (value == null) {
    return '';
  }
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
