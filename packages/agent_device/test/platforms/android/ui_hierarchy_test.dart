import 'package:agent_device/src/platforms/android/ui_hierarchy.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('ui_hierarchy', () {
    test('parseBounds parses valid bounds string', () {
      final rect = parseBounds('[0,0][100,200]');
      expect(rect, isNotNull);
      expect(rect!.x, 0);
      expect(rect.y, 0);
      expect(rect.width, 100);
      expect(rect.height, 200);
    });

    test('parseBounds returns null for invalid bounds', () {
      expect(parseBounds(null), isNull);
      expect(parseBounds(''), isNull);
      expect(parseBounds('invalid'), isNull);
      expect(parseBounds('[0,0]'), isNull);
    });

    test('parseBounds handles reverse coordinates', () {
      final rect = parseBounds('[100,200][0,0]');
      expect(rect, isNotNull);
      expect(rect!.width, 0);
      expect(rect.height, 0);
    });

    test('readNodeAttributes extracts all attributes', () {
      final node =
          '<node text="Hello" content-desc="Desc" '
          'resource-id="id/button" class="Button" '
          'bounds="[0,0][100,50]" clickable="true" enabled="false" />';
      final attrs = readNodeAttributes(node);

      expect(attrs.text, 'Hello');
      expect(attrs.desc, 'Desc');
      expect(attrs.resourceId, 'id/button');
      expect(attrs.className, 'Button');
      expect(attrs.clickable, true);
      expect(attrs.enabled, false);
      expect(attrs.bounds, '[0,0][100,50]');
    });

    test('readNodeAttributes handles missing attributes', () {
      final node = '<node />';
      final attrs = readNodeAttributes(node);

      expect(attrs.text, isNull);
      expect(attrs.desc, isNull);
      expect(attrs.clickable, isNull);
    });

    test('parseUiHierarchyTree builds simple tree', () {
      final xml = '''
        <hierarchy>
          <node class="FrameLayout" bounds="[0,0][1080,1920]">
            <node class="Button" text="Click me" bounds="[100,100][300,200]" clickable="true" />
          </node>
        </hierarchy>
      ''';

      final tree = parseUiHierarchyTree(xml);

      expect(tree.children, hasLength(1));
      expect(tree.children[0].type, 'FrameLayout');
      expect(tree.children[0].children, hasLength(1));
      expect(tree.children[0].children[0].label, 'Click me');
    });

    test('parseUiHierarchyTree handles self-closing nodes', () {
      final xml = '''
        <hierarchy>
          <node class="LinearLayout" bounds="[0,0][100,100]">
            <node class="View1" bounds="[0,0][50,50]" />
            <node class="View2" bounds="[50,0][100,50]" />
          </node>
        </hierarchy>
      ''';

      final tree = parseUiHierarchyTree(xml);
      expect(tree.children[0].children, hasLength(2));
    });

    test('parseUiHierarchy builds raw snapshot nodes', () {
      final xml = '''
        <hierarchy>
          <node class="Frame" bounds="[0,0][1080,1920]">
            <node class="Button" text="Submit" bounds="[400,100][680,200]" clickable="true" />
          </node>
        </hierarchy>
      ''';

      final result = parseUiHierarchy(xml, 100, const SnapshotOptions());

      expect(result.nodes, isNotEmpty);
      expect(result.analysis.rawNodeCount, 2);
      expect(result.analysis.maxDepth, 1);
    });

    test('parseUiHierarchy respects raw option', () {
      final xml = '''
        <hierarchy>
          <node class="Frame" bounds="[0,0][100,100]">
            <node class="View" bounds="[0,0][100,100]" />
          </node>
        </hierarchy>
      ''';

      final result = parseUiHierarchy(
        xml,
        100,
        const SnapshotOptions(raw: true),
      );

      expect(result.nodes, hasLength(2));
    });

    test('parseUiHierarchy respects maxNodes parameter', () {
      var xml = '<hierarchy>';
      // Create many interactive nodes to ensure they're included even with filtering
      for (var i = 0; i < 50; i++) {
        xml +=
            '<node class="Button" text="B$i" bounds="[0,$i][100,${i + 1}]" clickable="true" />';
      }
      xml += '</hierarchy>';

      final result = parseUiHierarchy(
        xml,
        10,
        const SnapshotOptions(raw: true),
      );

      // With raw mode, we get all nodes up to maxNodes
      expect(result.nodes.length, lessThanOrEqualTo(10));
      // If we hit the limit, truncated should be true
      if (result.nodes.length == 10) {
        expect(result.truncated ?? false, true);
      }
    });

    test('parseUiHierarchy respects depth limit', () {
      var xml = '<hierarchy>';
      xml += '<node class="L0" bounds="[0,0][100,100]">';
      xml += '<node class="L1" bounds="[0,0][100,100]">';
      xml += '<node class="L2" bounds="[0,0][100,100]">';
      xml += '<node class="L3" bounds="[0,0][100,100]" />';
      xml += '</node></node></node></hierarchy>';

      final result = parseUiHierarchy(
        xml,
        100,
        const SnapshotOptions(depth: 2),
      );

      final maxDepth = result.nodes.fold<int>(0, (max, n) {
        final d = n.depth ?? 0;
        return d > max ? d : max;
      });
      expect(maxDepth, lessThanOrEqualTo(2));
    });

    test('buildUiHierarchySnapshot applies interactive filter', () {
      final xml = '''
        <hierarchy>
          <node class="Frame" bounds="[0,0][100,100]">
            <node class="Button" text="Click" bounds="[10,10][90,40]" clickable="true" />
            <node class="View" bounds="[0,50][100,100]" />
          </node>
        </hierarchy>
      ''';

      final tree = parseUiHierarchyTree(xml);
      final built = buildUiHierarchySnapshot(
        tree,
        100,
        const SnapshotOptions(interactiveOnly: true),
      );

      expect(
        built.nodes.where((n) => (n.hittable ?? false)).length,
        greaterThan(0),
      );
    });

    test('findBounds locates nodes by text', () {
      final xml = '''
        <node text="Target Text" bounds="[100,200][300,300]" />
        <node text="Other" bounds="[0,0][50,50]" />
      ''';

      final bounds = findBounds(xml, 'target');
      expect(bounds, isNotNull);
      expect(bounds!.x, 200);
      expect(bounds.y, 250);
    });

    test('findBounds is case-insensitive', () {
      final xml = '<node text="HELLO WORLD" bounds="[0,0][100,100]" />';

      final bounds = findBounds(xml, 'hello');
      expect(bounds, isNotNull);
    });

    test('findBounds searches content-desc as fallback', () {
      final xml =
          '<node content-desc="Button Label" bounds="[50,50][150,150]" />';

      final bounds = findBounds(xml, 'button');
      expect(bounds, isNotNull);
    });

    test('AndroidSnapshotAnalysis reports correct stats', () {
      final xml = '''
        <hierarchy>
          <node class="Frame" bounds="[0,0][100,100]">
            <node class="Button" bounds="[10,10][40,40]">
              <node class="Text" bounds="[15,15][35,35]" />
            </node>
          </node>
        </hierarchy>
      ''';

      final tree = parseUiHierarchyTree(xml);
      final built = buildUiHierarchySnapshot(
        tree,
        100,
        const SnapshotOptions(),
      );

      expect(built.analysis.rawNodeCount, 3);
      expect(built.analysis.maxDepth, 2);
    });

    test('parseUiHierarchy handles empty hierarchy', () {
      final xml = '<hierarchy></hierarchy>';
      final result = parseUiHierarchy(xml, 100, const SnapshotOptions());

      expect(result.nodes, isEmpty);
    });

    test('parseUiHierarchy preserves node indices', () {
      final xml = '''
        <hierarchy>
          <node class="V1" bounds="[0,0][10,10]" />
          <node class="V2" bounds="[10,10][20,20]" />
          <node class="V3" bounds="[20,20][30,30]" />
        </hierarchy>
      ''';

      final result = parseUiHierarchy(xml, 100, const SnapshotOptions());

      for (var i = 0; i < result.nodes.length; i++) {
        expect(result.nodes[i].index, i);
      }
    });
  });
}
