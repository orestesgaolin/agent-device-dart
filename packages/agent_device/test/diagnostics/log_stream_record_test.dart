// Unit coverage for the shared LogStreamRecord payload.

import 'dart:convert';

import 'package:agent_device/src/diagnostics/log_stream_record.dart';
import 'package:test/test.dart';

void main() {
  group('LogStreamRecord', () {
    test('round-trips via toJson / fromJson', () {
      const r = LogStreamRecord(
        deviceId: 'UDID-123',
        platform: 'ios',
        hostPid: 42,
        outPath: '/tmp/safari.log',
        startedAt: '2026-04-24T12:00:00Z',
        appBundleId: 'com.apple.mobilesafari',
      );
      final encoded = jsonEncode(r.toJson());
      final decoded = LogStreamRecord.fromJson(jsonDecode(encoded));
      expect(decoded, isNotNull);
      expect(decoded!.deviceId, 'UDID-123');
      expect(decoded.platform, 'ios');
      expect(decoded.hostPid, 42);
      expect(decoded.outPath, '/tmp/safari.log');
      expect(decoded.startedAt, '2026-04-24T12:00:00Z');
      expect(decoded.appBundleId, 'com.apple.mobilesafari');
    });

    test('appBundleId is optional', () {
      const r = LogStreamRecord(
        deviceId: 'emulator-5554',
        platform: 'android',
        hostPid: 7,
        outPath: '/tmp/logcat.log',
        startedAt: '2026-04-24T12:01:00Z',
      );
      final decoded = LogStreamRecord.fromJson(
        jsonDecode(jsonEncode(r.toJson())),
      );
      expect(decoded!.appBundleId, isNull);
    });

    test('fromJson rejects malformed payloads', () {
      expect(LogStreamRecord.fromJson(null), isNull);
      expect(LogStreamRecord.fromJson('not a map'), isNull);
      expect(
        LogStreamRecord.fromJson({
          'deviceId': 'a',
          'platform': 'ios',
          // hostPid missing
          'outPath': '/tmp/x.log',
          'startedAt': 't',
        }),
        isNull,
      );
      expect(
        LogStreamRecord.fromJson({
          'deviceId': 'a',
          'platform': 'ios',
          'hostPid': 'not-an-int', // wrong type
          'outPath': '/tmp/x.log',
          'startedAt': 't',
        }),
        isNull,
      );
    });
  });
}
