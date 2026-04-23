// Port of agent-device/src/platforms/appearance.ts

import '../utils/errors.dart';

enum AppearanceAction {
  light('light'),
  dark('dark'),
  toggle('toggle');

  final String value;

  const AppearanceAction(this.value);

  static AppearanceAction fromString(String value) {
    return switch (value.trim().toLowerCase()) {
      'light' => AppearanceAction.light,
      'dark' => AppearanceAction.dark,
      'toggle' => AppearanceAction.toggle,
      _ => throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid appearance state: $value. Use light|dark|toggle.',
      ),
    };
  }

  @override
  String toString() => value;
}
