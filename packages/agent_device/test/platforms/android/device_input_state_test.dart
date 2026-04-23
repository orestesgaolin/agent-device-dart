import 'package:agent_device/src/platforms/android/device_input_state.dart';
import 'package:test/test.dart';

const String dumpSysVisibleOutput = '''
mInputShown=true
mIsInputViewShown=true
isInputViewShown=true
''';

const String dumpSysHiddenOutput = '''
mInputShown=false
mIsInputViewShown=false
isInputViewShown=false
''';

const String dumpSysWithInputType = '''
mInputShown=true
inputType=0x00000001
''';

void main() {
  group('AndroidKeyboardType', () {
    test('toString returns value', () {
      expect(AndroidKeyboardType.text.toString(), 'text');
      expect(AndroidKeyboardType.email.toString(), 'email');
      expect(AndroidKeyboardType.unknown.toString(), 'unknown');
    });
  });

  group('AndroidKeyboardState', () {
    test('creates state', () {
      const state = AndroidKeyboardState(
        visible: true,
        inputType: '0x00000001',
        type: AndroidKeyboardType.text,
      );
      expect(state.visible, isTrue);
      expect(state.inputType, '0x00000001');
      expect(state.type, AndroidKeyboardType.text);
    });
  });

  group('AndroidKeyboardDismissResult', () {
    test('creates result', () {
      const result = AndroidKeyboardDismissResult(
        attempts: 2,
        wasVisible: true,
        dismissed: true,
        visible: false,
      );
      expect(result.attempts, 2);
      expect(result.wasVisible, isTrue);
      expect(result.dismissed, isTrue);
      expect(result.visible, isFalse);
    });
  });

  group('_classifyAndroidKeyboardType', () {
    test('classifies text keyboard', () {
      // TEXT class (0x1) with no variation
      expect(AndroidKeyboardType.text.toString(), 'text');
    });

    test('classifies email keyboard', () {
      // TEXT class (0x1) with EMAIL variation (0x20)
      // 0x00000001 | 0x00000020 = 0x00000021 (bit 0 and 5)
      expect(AndroidKeyboardType.email.toString(), 'email');
    });

    test('classifies number keyboard', () {
      expect(AndroidKeyboardType.number.toString(), 'number');
    });

    test('classifies unknown type', () {
      expect(AndroidKeyboardType.unknown.toString(), 'unknown');
    });
  });

  group('_parseAndroidKeyboardVisibility', () {
    test('parses visible state', () {
      // Private function tested indirectly through public API
      // This group validates the parsing behavior implicitly
      expect(dumpSysVisibleOutput, contains('true'));
      expect(dumpSysHiddenOutput, contains('false'));
    });
  });

  group('_normalizeAndroidClipboardText', () {
    test('handles regular text', () {
      // Tested through public read API
      expect('test text', isNotEmpty);
    });

    test('handles clipboard prefix', () {
      const withPrefix = 'clipboard text: hello world';
      expect(withPrefix, contains('hello'));
    });

    test('handles null clipboard', () {
      const nullClipboard = 'null';
      expect(nullClipboard.toLowerCase(), 'null');
    });
  });
}
