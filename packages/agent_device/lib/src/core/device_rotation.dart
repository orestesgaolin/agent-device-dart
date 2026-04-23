// Port of agent-device/src/core/device-rotation.ts

import '../utils/errors.dart';

enum DeviceRotation {
  portrait('portrait'),
  portraitUpsideDown('portrait-upside-down'),
  landscapeLeft('landscape-left'),
  landscapeRight('landscape-right');

  final String value;

  const DeviceRotation(this.value);

  static DeviceRotation fromString(String? input) {
    if (input == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'rotate requires an orientation argument. Use portrait|portrait-upside-down|landscape-left|landscape-right.',
      );
    }

    final normalized = input.trim().toLowerCase();
    return switch (normalized) {
      'portrait' => DeviceRotation.portrait,
      'portrait-upside-down' ||
      'upside-down' => DeviceRotation.portraitUpsideDown,
      'landscape-left' || 'left' => DeviceRotation.landscapeLeft,
      'landscape-right' || 'right' => DeviceRotation.landscapeRight,
      _ => throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid rotation: $input. Use portrait|portrait-upside-down|landscape-left|landscape-right.',
      ),
    };
  }

  @override
  String toString() => value;
}
