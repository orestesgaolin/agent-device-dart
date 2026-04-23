import 'package:agent_device/src/platforms/android/notifications.dart';
import 'package:test/test.dart';

void main() {
  group('AndroidBroadcastPayload', () {
    test('creates with default action', () {
      final payload = const AndroidBroadcastPayload();
      expect(payload.action, isNull);
      expect(payload.receiver, isNull);
      expect(payload.extras, isNull);
    });

    test('creates with all fields', () {
      final extras = {'key': 'value'};
      final payload = AndroidBroadcastPayload(
        action: 'com.test.ACTION',
        receiver: 'com.test/.MainActivity',
        extras: extras,
      );
      expect(payload.action, 'com.test.ACTION');
      expect(payload.receiver, 'com.test/.MainActivity');
      expect(payload.extras, extras);
    });
  });

  group('AndroidNotificationResult', () {
    test('creates result', () {
      final result = const AndroidNotificationResult(
        action: 'com.test.ACTION',
        extrasCount: 3,
      );
      expect(result.action, 'com.test.ACTION');
      expect(result.extrasCount, 3);
    });
  });

  group('AndroidPayload composition', () {
    test('accepts various payload structures', () {
      final payload1 = const AndroidBroadcastPayload();
      expect(payload1.action, isNull);

      final payload2 = const AndroidBroadcastPayload(
        action: 'test',
        extras: {'key': 'value'},
      );
      expect(payload2.action, 'test');
      expect(payload2.extras, isNotEmpty);
    });
  });
}
