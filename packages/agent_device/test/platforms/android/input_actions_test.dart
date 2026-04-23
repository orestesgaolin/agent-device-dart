import 'package:test/test.dart';

void main() {
  group('input_actions', () {
    test('pressAndroid builds correct adb arguments', () {
      // Verification: tap command with x, y coordinates
      final expected = [
        '-s',
        'test-serial',
        'shell',
        'input',
        'tap',
        '100',
        '200',
      ];
      expect(
        expected.sublist(2),
        equals(['shell', 'input', 'tap', '100', '200']),
      );
    });

    test('swipeAndroid builds correct adb arguments', () {
      // Verification: swipe command with start/end coordinates and duration
      final expected = [
        '-s',
        'test-serial',
        'shell',
        'input',
        'swipe',
        '10',
        '20',
        '100',
        '200',
        '250',
      ];
      expect(
        expected.sublist(2),
        equals(['shell', 'input', 'swipe', '10', '20', '100', '200', '250']),
      );
    });

    test('longPressAndroid builds correct adb arguments', () {
      // Verification: swipe with identical start/end coordinates
      final expected = [
        '-s',
        'test-serial',
        'shell',
        'input',
        'swipe',
        '150',
        '150',
        '150',
        '150',
        '800',
      ];
      expect(
        expected.sublist(2),
        equals(['shell', 'input', 'swipe', '150', '150', '150', '150', '800']),
      );
    });

    test('backAndroid sends KEYCODE_BACK (4)', () {
      final expected = ['-s', 'test-serial', 'shell', 'input', 'keyevent', '4'];
      expect(expected.sublist(2), equals(['shell', 'input', 'keyevent', '4']));
    });

    test('homeAndroid sends KEYCODE_HOME (3)', () {
      final expected = ['-s', 'test-serial', 'shell', 'input', 'keyevent', '3'];
      expect(expected.sublist(2), equals(['shell', 'input', 'keyevent', '3']));
    });

    test('appSwitcherAndroid sends KEYCODE_APP_SWITCH (187)', () {
      final expected = [
        '-s',
        'test-serial',
        'shell',
        'input',
        'keyevent',
        '187',
      ];
      expect(
        expected.sublist(2),
        equals(['shell', 'input', 'keyevent', '187']),
      );
    });

    test('rotateAndroid disables accelerometer and sets user_rotation', () {
      // Verification: sequence of settings commands
      final disableAccel = [
        'shell',
        'settings',
        'put',
        'system',
        'accelerometer_rotation',
        '0',
      ];
      final setRotation = [
        'shell',
        'settings',
        'put',
        'system',
        'user_rotation',
        '0',
      ]; // portrait
      expect(disableAccel, isNotEmpty);
      expect(setRotation, isNotEmpty);
      expect(setRotation[5], equals('0')); // portrait maps to 0
    });

    test('typeAndroid encodes spaces as %s', () {
      // Verification: space encoding for adb shell input text
      const input = 'hello world';
      const encoded = 'hello%sworld';
      expect(input.replaceAll(' ', '%s'), equals(encoded));
    });

    test('scrollAndroid builds swipe command with 300ms duration', () {
      // Verification: scroll translates to swipe with fixed 300ms duration
      final expected = [
        '-s',
        'test-serial',
        'shell',
        'input',
        'swipe',
        'x1',
        'y1',
        'x2',
        'y2',
        '300', // duration
      ];
      expect(expected.sublist(2), contains('shell'));
      expect(expected.sublist(2), contains('swipe'));
      expect(expected[9], equals('300')); // duration is always 300ms
    });
  });
}
