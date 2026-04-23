// Port of agent-device/src/platforms/permission-utils.ts

import '../utils/errors.dart';

enum PermissionAction {
  grant('grant'),
  deny('deny'),
  reset('reset');

  final String value;

  const PermissionAction(this.value);

  static PermissionAction fromString(String action) {
    return switch (action.trim().toLowerCase()) {
      'grant' => PermissionAction.grant,
      'deny' => PermissionAction.deny,
      'reset' => PermissionAction.reset,
      _ => throw AppError(
        AppErrorCodes.invalidArgs,
        'Invalid permission action: $action. Use grant|deny|reset.',
      ),
    };
  }

  @override
  String toString() => value;
}

enum PermissionTarget {
  camera('camera'),
  microphone('microphone'),
  photos('photos'),
  contacts('contacts'),
  contactsLimited('contacts-limited'),
  notifications('notifications'),
  calendar('calendar'),
  location('location'),
  locationAlways('location-always'),
  mediaLibrary('media-library'),
  motion('motion'),
  reminders('reminders'),
  siri('siri');

  final String value;

  const PermissionTarget(this.value);

  static const List<PermissionTarget> allTargets = [
    PermissionTarget.camera,
    PermissionTarget.microphone,
    PermissionTarget.photos,
    PermissionTarget.contacts,
    PermissionTarget.contactsLimited,
    PermissionTarget.notifications,
    PermissionTarget.calendar,
    PermissionTarget.location,
    PermissionTarget.locationAlways,
    PermissionTarget.mediaLibrary,
    PermissionTarget.motion,
    PermissionTarget.reminders,
    PermissionTarget.siri,
  ];

  static PermissionTarget fromString(String? value) {
    if (value == null) {
      throw AppError(
        AppErrorCodes.invalidArgs,
        'permission setting requires a target: ${allTargets.map((t) => t.value).join('|')}',
      );
    }

    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'camera' => PermissionTarget.camera,
      'microphone' => PermissionTarget.microphone,
      'photos' => PermissionTarget.photos,
      'contacts' => PermissionTarget.contacts,
      'contacts-limited' => PermissionTarget.contactsLimited,
      'notifications' => PermissionTarget.notifications,
      'calendar' => PermissionTarget.calendar,
      'location' => PermissionTarget.location,
      'location-always' => PermissionTarget.locationAlways,
      'media-library' => PermissionTarget.mediaLibrary,
      'motion' => PermissionTarget.motion,
      'reminders' => PermissionTarget.reminders,
      'siri' => PermissionTarget.siri,
      _ => throw AppError(
        AppErrorCodes.invalidArgs,
        'permission setting requires a target: ${allTargets.map((t) => t.value).join('|')}',
      ),
    };
  }

  @override
  String toString() => value;
}
