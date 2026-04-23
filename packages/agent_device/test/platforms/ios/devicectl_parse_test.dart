// Unit coverage for the devicectl JSON payload parsers. These run on
// every host because they don't shell out — they just exercise the
// pure-Dart mapping functions against sample payloads.

import 'dart:convert';

import 'package:agent_device/src/platforms/ios/devicectl.dart';
import 'package:test/test.dart';

void main() {
  group('parseIosDeviceAppsPayload', () {
    test('maps bundleIdentifier + name + url', () {
      final payload = jsonDecode('''
{
  "result": {
    "apps": [
      {"bundleIdentifier": "com.example.foo", "name": "Foo App", "url": "file:///a/Foo.app"},
      {"bundleIdentifier": "com.example.bar", "name": "", "url": ""}
    ]
  }
}
''');
      final parsed = parseIosDeviceAppsPayload(payload);
      expect(parsed, hasLength(2));
      expect(parsed[0].bundleId, 'com.example.foo');
      expect(parsed[0].name, 'Foo App');
      expect(parsed[0].url, 'file:///a/Foo.app');
      expect(parsed[1].bundleId, 'com.example.bar');
      expect(
        parsed[1].name,
        'com.example.bar',
        reason: 'Empty name should fall back to bundleId.',
      );
      expect(parsed[1].url, isNull);
    });

    test('tolerates malformed / empty payloads', () {
      expect(parseIosDeviceAppsPayload(null), isEmpty);
      expect(parseIosDeviceAppsPayload({'result': null}), isEmpty);
      expect(
        parseIosDeviceAppsPayload({'result': <String, Object?>{}}),
        isEmpty,
      );
      expect(
        parseIosDeviceAppsPayload({
          'result': {'apps': 'not a list'},
        }),
        isEmpty,
      );
    });

    test('skips entries missing bundleIdentifier', () {
      final payload = jsonDecode('''
{"result": {"apps": [{"name": "no-id"}, {"bundleIdentifier": "   "}]}}
''');
      expect(parseIosDeviceAppsPayload(payload), isEmpty);
    });
  });
}
