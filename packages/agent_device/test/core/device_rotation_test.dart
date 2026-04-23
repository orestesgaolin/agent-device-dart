import 'package:agent_device/src/core/device_rotation.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceRotation', () {
    test('parses portrait', () {
      expect(DeviceRotation.fromString('portrait'), DeviceRotation.portrait);
      expect(DeviceRotation.fromString('PORTRAIT'), DeviceRotation.portrait);
      expect(
        DeviceRotation.fromString('  portrait  '),
        DeviceRotation.portrait,
      );
    });

    test('parses landscape-left aliases', () {
      expect(
        DeviceRotation.fromString('landscape-left'),
        DeviceRotation.landscapeLeft,
      );
      expect(DeviceRotation.fromString('left'), DeviceRotation.landscapeLeft);
      expect(DeviceRotation.fromString('LEFT'), DeviceRotation.landscapeLeft);
    });

    test('parses landscape-right aliases', () {
      expect(
        DeviceRotation.fromString('landscape-right'),
        DeviceRotation.landscapeRight,
      );
      expect(DeviceRotation.fromString('right'), DeviceRotation.landscapeRight);
      expect(DeviceRotation.fromString('RIGHT'), DeviceRotation.landscapeRight);
    });

    test('parses portrait-upside-down aliases', () {
      expect(
        DeviceRotation.fromString('portrait-upside-down'),
        DeviceRotation.portraitUpsideDown,
      );
      expect(
        DeviceRotation.fromString('upside-down'),
        DeviceRotation.portraitUpsideDown,
      );
      expect(
        DeviceRotation.fromString('UPSIDE-DOWN'),
        DeviceRotation.portraitUpsideDown,
      );
    });

    test('throws on invalid rotation', () {
      expect(
        () => DeviceRotation.fromString('invalid'),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.invalidArgs)
              .having(
                (e) => e.message,
                'message',
                contains('Invalid rotation'),
              ),
        ),
      );
    });

    test('throws on null input', () {
      expect(
        () => DeviceRotation.fromString(null),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.invalidArgs)
              .having((e) => e.message, 'message', contains('rotate requires')),
        ),
      );
    });

    test('toString returns value', () {
      expect(DeviceRotation.portrait.toString(), 'portrait');
      expect(DeviceRotation.landscapeLeft.toString(), 'landscape-left');
    });
  });
}
