import 'package:agent_device/src/core/open_target.dart';
import 'package:test/test.dart';

void main() {
  group('isDeepLinkTarget', () {
    test('returns true for valid deep links', () {
      expect(isDeepLinkTarget('myapp://path'), isTrue);
      expect(isDeepLinkTarget('com.example://action'), isTrue);
      expect(isDeepLinkTarget('http://example.com'), isTrue);
      expect(isDeepLinkTarget('https://example.com'), isTrue);
      expect(isDeepLinkTarget('ftp://ftp.example.com'), isTrue);
    });

    test('returns false for invalid deep links', () {
      expect(isDeepLinkTarget(''), isFalse);
      expect(isDeepLinkTarget('   '), isFalse);
      expect(isDeepLinkTarget('no space allowed'), isFalse);
      expect(isDeepLinkTarget('https:/missing-slash'), isFalse);
    });

    test('validates scheme format', () {
      expect(isDeepLinkTarget('9invalid://path'), isFalse);
      expect(isDeepLinkTarget('-invalid://path'), isFalse);
      expect(isDeepLinkTarget('valid+scheme://path'), isTrue);
    });
  });

  group('isWebUrl', () {
    test('returns true for http/https', () {
      expect(isWebUrl('http://example.com'), isTrue);
      expect(isWebUrl('https://example.com'), isTrue);
      expect(isWebUrl('HTTP://EXAMPLE.COM'), isTrue);
    });

    test('returns false for non-web schemes', () {
      expect(isWebUrl('ftp://example.com'), isFalse);
      expect(isWebUrl('myapp://path'), isFalse);
      expect(isWebUrl('mailto:test@example.com'), isFalse);
    });
  });

  group('resolveIosDeviceDeepLinkBundleId', () {
    test('returns provided bundle ID if given', () {
      expect(
        resolveIosDeviceDeepLinkBundleId('com.app.test', 'http://example.com'),
        'com.app.test',
      );
      expect(
        resolveIosDeviceDeepLinkBundleId('com.app.test', 'myapp://path'),
        'com.app.test',
      );
    });

    test('returns Safari bundle ID for web URLs', () {
      expect(
        resolveIosDeviceDeepLinkBundleId(null, 'http://example.com'),
        iosSafariBundleId,
      );
      expect(
        resolveIosDeviceDeepLinkBundleId(null, 'https://example.com'),
        iosSafariBundleId,
      );
    });

    test('returns null for non-web deep links without bundle ID', () {
      expect(resolveIosDeviceDeepLinkBundleId(null, 'myapp://path'), isNull);
    });

    test('ignores whitespace in bundle ID', () {
      expect(
        resolveIosDeviceDeepLinkBundleId(
          '  com.app.test  ',
          'http://example.com',
        ),
        'com.app.test',
      );
    });
  });
}
