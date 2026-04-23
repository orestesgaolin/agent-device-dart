import 'package:agent_device/src/platforms/permission_utils.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('PermissionAction', () {
    test('parses valid actions', () {
      expect(PermissionAction.fromString('grant'), PermissionAction.grant);
      expect(PermissionAction.fromString('deny'), PermissionAction.deny);
      expect(PermissionAction.fromString('reset'), PermissionAction.reset);
    });

    test('parses case-insensitively', () {
      expect(PermissionAction.fromString('GRANT'), PermissionAction.grant);
      expect(PermissionAction.fromString('Deny'), PermissionAction.deny);
      expect(PermissionAction.fromString('  reset  '), PermissionAction.reset);
    });

    test('throws on invalid action', () {
      expect(
        () => PermissionAction.fromString('invalid'),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.invalidArgs)
              .having(
                (e) => e.message,
                'message',
                contains('Invalid permission action'),
              ),
        ),
      );
    });

    test('toString returns value', () {
      expect(PermissionAction.grant.toString(), 'grant');
      expect(PermissionAction.deny.toString(), 'deny');
    });
  });

  group('PermissionTarget', () {
    test('parses all valid targets', () {
      final targets = [
        ('camera', PermissionTarget.camera),
        ('microphone', PermissionTarget.microphone),
        ('photos', PermissionTarget.photos),
        ('contacts', PermissionTarget.contacts),
        ('contacts-limited', PermissionTarget.contactsLimited),
        ('notifications', PermissionTarget.notifications),
        ('calendar', PermissionTarget.calendar),
        ('location', PermissionTarget.location),
        ('location-always', PermissionTarget.locationAlways),
        ('media-library', PermissionTarget.mediaLibrary),
        ('motion', PermissionTarget.motion),
        ('reminders', PermissionTarget.reminders),
        ('siri', PermissionTarget.siri),
      ];

      for (final (str, target) in targets) {
        expect(PermissionTarget.fromString(str), target);
      }
    });

    test('parses case-insensitively', () {
      expect(PermissionTarget.fromString('CAMERA'), PermissionTarget.camera);
      expect(
        PermissionTarget.fromString('Location-Always'),
        PermissionTarget.locationAlways,
      );
    });

    test('throws on null', () {
      expect(
        () => PermissionTarget.fromString(null),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.invalidArgs)
              .having(
                (e) => e.message,
                'message',
                contains('permission setting requires'),
              ),
        ),
      );
    });

    test('throws on invalid target', () {
      expect(
        () => PermissionTarget.fromString('invalid'),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            AppErrorCodes.invalidArgs,
          ),
        ),
      );
    });

    test('toString returns value', () {
      expect(PermissionTarget.camera.toString(), 'camera');
      expect(PermissionTarget.locationAlways.toString(), 'location-always');
    });

    test('allTargets list has all targets', () {
      expect(PermissionTarget.allTargets.length, 13);
      expect(PermissionTarget.allTargets, contains(PermissionTarget.camera));
      expect(PermissionTarget.allTargets, contains(PermissionTarget.siri));
    });
  });
}
