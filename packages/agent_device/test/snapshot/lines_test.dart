import 'package:agent_device/src/snapshot/lines.dart';
import 'package:agent_device/src/snapshot/snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('lines.dart', () {
    test('formatRole normalizes XCUIElementType strings', () {
      expect(formatRole('XCUIElementTypeButton'), equals('button'));
      expect(formatRole('XCUIElementTypeStaticText'), equals('text'));
      expect(formatRole('button'), equals('button'));
      expect(formatRole('android.widget.Button'), equals('button'));
    });

    test('displayLabel extracts meaningful text', () {
      final button = SnapshotNode(
        index: 0,
        ref: 'e1',
        type: 'button',
        label: 'Submit',
      );
      expect(displayLabel(button, 'button'), equals('Submit'));

      final textField = SnapshotNode(
        index: 1,
        ref: 'e2',
        type: 'text-field',
        value: 'user input',
      );
      expect(displayLabel(textField, 'text-field'), equals('user input'));
    });

    test('buildSnapshotDisplayLines filters and indents nodes', () {
      final nodes = [
        SnapshotNode(index: 0, ref: 'e1', type: 'window', depth: 0),
        SnapshotNode(
          index: 1,
          ref: 'e2',
          type: 'button',
          label: 'Click me',
          depth: 1,
        ),
        SnapshotNode(index: 2, ref: 'e3', type: 'group', depth: 2),
      ];

      final lines = buildSnapshotDisplayLinesPublic(nodes);
      expect(lines.length, equals(2)); // group without label is filtered
      expect(lines[0].text.startsWith('@e1'), isTrue);
      expect(lines[1].text.startsWith('  @e2'), isTrue); // indented
    });

    test('formatSnapshotLine includes metadata', () {
      final node = SnapshotNode(
        index: 0,
        ref: 'e1',
        type: 'button',
        label: 'OK',
        enabled: false,
      );

      final line = formatSnapshotLine(
        node,
        0,
        false,
        'button',
        const SnapshotLineFormatOptions(),
      );
      expect(line.contains('[button]'), isTrue);
      expect(line.contains('[disabled]'), isTrue);
      expect(line.contains('OK'), isTrue);
    });

    test('formatSnapshotLine handles editable fields', () {
      final node = SnapshotNode(
        index: 0,
        ref: 'e1',
        type: 'text-field',
        label: 'Username',
      );

      final options = const SnapshotLineFormatOptions(
        summarizeTextSurfaces: true,
      );
      final line = formatSnapshotLine(node, 0, false, 'text-field', options);
      expect(line.contains('text-field'), isTrue);
      expect(line.contains('editable'), isTrue);
    });
  });
}
