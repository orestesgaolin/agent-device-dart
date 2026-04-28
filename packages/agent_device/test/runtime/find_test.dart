import 'package:agent_device/agent_device.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fake backend that returns a canned snapshot.
// ---------------------------------------------------------------------------

class _FakeBackend extends Backend {
  final BackendSnapshotResult _snapshot;

  _FakeBackend(this._snapshot);

  @override
  AgentDeviceBackendPlatform get platform => AgentDeviceBackendPlatform.android;

  @override
  Future<List<BackendDeviceInfo>> listDevices(
    BackendCommandContext ctx, [
    BackendDeviceFilter? filter,
  ]) async => [
    const BackendDeviceInfo(
      id: 'emulator-5554',
      name: 'Pixel 9 Pro',
      platform: AgentDeviceBackendPlatform.android,
    ),
  ];

  @override
  Future<BackendSnapshotResult> captureSnapshot(
    BackendCommandContext ctx,
    BackendSnapshotOptions? options,
  ) async => _snapshot;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a raw snapshot from a list of `(label, type)` tuples.
BackendSnapshotResult _makeSnapshot(
  List<({String? label, String type, String? value, String? id})> entries,
) {
  final nodes = <SnapshotNode>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    nodes.add(
      SnapshotNode(
        index: i,
        ref: 'e${i + 1}',
        label: e.label,
        type: e.type,
        value: e.value,
        identifier: e.id,
        hittable: true,
      ),
    );
  }
  return BackendSnapshotResult(nodes: nodes);
}

Future<AgentDevice> _openDevice(BackendSnapshotResult snap) async {
  return AgentDevice.open(backend: _FakeBackend(snap));
}

// ---------------------------------------------------------------------------
// Test nodes used across groups.
// ---------------------------------------------------------------------------

typedef _Node = ({String? label, String type, String? value, String? id});

const _Node _yesNode = (
  label: 'Yes, Tap to select',
  type: 'android.view.View',
  value: null,
  id: null,
);
const _Node _noNode = (
  label: 'No, Tap to select',
  type: 'android.view.View',
  value: null,
  id: null,
);
const _Node _questionNode = (
  label: 'Do your symptoms get worse?',
  type: 'android.widget.TextView',
  value: null,
  id: null,
);
const _Node _editNode = (
  label: null,
  type: 'android.widget.EditText',
  value: 'typed value',
  id: 'com.example:id/edit',
);
const _Node _buttonNode = (
  label: 'Submit',
  type: 'android.widget.Button',
  value: null,
  id: null,
);

void main() {
  group('AgentDevice.find — plain substring mode', () {
    late AgentDevice device;

    setUp(() async {
      final snap = _makeSnapshot([_yesNode, _noNode, _questionNode]);
      device = await _openDevice(snap);
    });

    test('finds node by exact label (case-insensitive)', () async {
      final hits = await device.find('Yes, Tap to select');
      expect(hits, hasLength(1));
      expect(hits.first['label'], 'Yes, Tap to select');
    });

    test('finds node by partial label', () async {
      final hits = await device.find('Yes');
      expect(hits, hasLength(1));
      expect(hits.first['label'], 'Yes, Tap to select');
    });

    test('is case-insensitive', () async {
      final hits = await device.find('yes, tap to select');
      expect(hits, hasLength(1));
    });

    test('normalises whitespace in query', () async {
      final hits = await device.find('Yes,  Tap  to  select');
      expect(hits, hasLength(1));
    });

    test('returns multiple matches when query is broad', () async {
      final hits = await device.find('Tap to select');
      expect(hits, hasLength(2));
    });

    test('returns empty list when nothing matches', () async {
      final hits = await device.find('xyz_no_match');
      expect(hits, isEmpty);
    });

    test('result map contains ref, label, type', () async {
      final hits = await device.find('Yes');
      final h = hits.first;
      expect(h.containsKey('ref'), isTrue);
      expect(h['label'], 'Yes, Tap to select');
      expect(h['type'], 'android.view.View');
    });
  });

  group('AgentDevice.find — locator token mode', () {
    late AgentDevice device;

    setUp(() async {
      final snap = _makeSnapshot([_yesNode, _noNode, _editNode, _buttonNode]);
      device = await _openDevice(snap);
    });

    test('locator=label searches only label', () async {
      final hits = await device.find('Yes', locator: 'label');
      expect(hits, hasLength(1));
      expect(hits.first['label'], 'Yes, Tap to select');
    });

    test('locator=label misses value-only node', () async {
      // editNode has no label, only value
      final hits = await device.find('typed', locator: 'label');
      expect(hits, isEmpty);
    });

    test('locator=value searches only value', () async {
      final hits = await device.find('typed', locator: 'value');
      expect(hits, hasLength(1));
      expect(hits.first['value'], 'typed value');
    });

    test('locator=value misses label-only node', () async {
      final hits = await device.find('Submit', locator: 'value');
      expect(hits, isEmpty);
    });

    test('locator=id searches identifier', () async {
      final hits = await device.find('edit', locator: 'id');
      expect(hits, hasLength(1));
      expect(hits.first['identifier'], 'com.example:id/edit');
    });

    test('locator=role searches normalized type', () async {
      // 'android.widget.Button' → normalized last segment 'button'
      final hits = await device.find('button', locator: 'role');
      expect(hits, hasLength(1));
      expect(hits.first['type'], 'android.widget.Button');
    });

    test('locator=role is case-insensitive', () async {
      final hits = await device.find('Button', locator: 'role');
      expect(hits, hasLength(1));
    });

    test('locator=text searches label, value, identifier', () async {
      // editNode matches via value; yesNode via label
      final hits = await device.find('yes', locator: 'text');
      expect(hits, hasLength(1));
      expect(hits.first['label'], 'Yes, Tap to select');
    });

    test('locator=any (default) searches label, value, identifier', () async {
      final hits = await device.find('typed', locator: 'any');
      expect(hits, hasLength(1));
      expect(hits.first['value'], 'typed value');
    });
  });

  group('AgentDevice.find — selector DSL mode', () {
    late AgentDevice device;

    setUp(() async {
      final snap = _makeSnapshot([_yesNode, _noNode, _questionNode, _buttonNode]);
      device = await _openDevice(snap);
    });

    test('text= exact match finds correct node', () async {
      final chain = parseSelectorChain('text="Yes, Tap to select"');
      final hits = await device.find('', selectorChain: chain);
      expect(hits, hasLength(1));
      expect(hits.first['label'], 'Yes, Tap to select');
    });

    test('text= exact match is case-insensitive', () async {
      final chain = parseSelectorChain('text="yes, tap to select"');
      final hits = await device.find('', selectorChain: chain);
      expect(hits, hasLength(1));
    });

    test('text= exact match does not match partial label', () async {
      // "Yes" alone doesn't equal "Yes, Tap to select"
      final chain = parseSelectorChain('text=Yes');
      final hits = await device.find('', selectorChain: chain);
      expect(hits, isEmpty);
    });

    test('label= matches label field exactly', () async {
      final chain = parseSelectorChain('label="No, Tap to select"');
      final hits = await device.find('', selectorChain: chain);
      expect(hits, hasLength(1));
      expect(hits.first['label'], 'No, Tap to select');
    });

    test('role= matches normalized type', () async {
      // 'android.widget.Button' → last segment 'button'
      final chain = parseSelectorChain('role=button');
      final hits = await device.find('', selectorChain: chain);
      expect(hits, hasLength(1));
      expect(hits.first['type'], 'android.widget.Button');
    });

    test('selector with multiple terms narrows results', () async {
      // role=view matches both yesNode and noNode; text="Yes..." further narrows
      final chain = parseSelectorChain('role=view text="Yes, Tap to select"');
      final hits = await device.find('', selectorChain: chain);
      expect(hits, hasLength(1));
      expect(hits.first['label'], 'Yes, Tap to select');
    });

    test('fallback chain returns first alternative that matches', () async {
      // First alternative misses; second matches.
      final chain = parseSelectorChain(
        'text="Nonexistent" || text="No, Tap to select"',
      );
      final hits = await device.find('', selectorChain: chain);
      expect(hits, hasLength(1));
      expect(hits.first['label'], 'No, Tap to select');
    });
  });

  group('AgentDevice.find — edge cases', () {
    test('throws on empty query when no selectorChain', () async {
      final snap = _makeSnapshot([_yesNode]);
      final device = await _openDevice(snap);
      expect(() => device.find(''), throwsA(isA<AppError>()));
    });

    test('empty snapshot returns empty list', () async {
      final snap = _makeSnapshot([]);
      final device = await _openDevice(snap);
      final hits = await device.find('anything');
      expect(hits, isEmpty);
    });
  });
}
