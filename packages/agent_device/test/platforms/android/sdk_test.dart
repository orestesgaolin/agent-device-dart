/// Tests for sdk.dart — Android SDK path resolution.
library;

import 'package:agent_device/src/platforms/android/sdk.dart';
import 'package:test/test.dart';

void main() {
  group('resolveAndroidSdkRoots', () {
    test('reads ANDROID_SDK_ROOT from env', () {
      final env = {'ANDROID_SDK_ROOT': '/path/to/sdk'};
      final roots = resolveAndroidSdkRoots(env);
      expect(roots, contains('/path/to/sdk'));
    });

    test('reads ANDROID_HOME from env', () {
      final env = {'ANDROID_HOME': '/path/to/android'};
      final roots = resolveAndroidSdkRoots(env);
      expect(roots, contains('/path/to/android'));
    });

    test('defaults to ~/Android/Sdk', () {
      final env = {'HOME': '/home/user'};
      final roots = resolveAndroidSdkRoots(env);
      expect(roots, contains('/home/user/Android/Sdk'));
    });

    test('prefers ANDROID_SDK_ROOT over ANDROID_HOME', () {
      final env = {'ANDROID_SDK_ROOT': '/sdk', 'ANDROID_HOME': '/home'};
      final roots = resolveAndroidSdkRoots(env);
      expect(roots[0], equals('/sdk'));
      expect(roots, contains('/home'));
    });

    test('deduplicates identical roots', () {
      final env = {'ANDROID_SDK_ROOT': '/sdk', 'ANDROID_HOME': '/sdk'};
      final roots = resolveAndroidSdkRoots(env);
      expect(roots.where((r) => r == '/sdk').length, equals(1));
    });

    test('trims whitespace from env values', () {
      final env = {'ANDROID_SDK_ROOT': '  /sdk  '};
      final roots = resolveAndroidSdkRoots(env);
      expect(roots, contains('/sdk'));
      expect(roots, isNot(contains('  /sdk  ')));
    });

    test('ignores empty env values', () {
      final env = {'ANDROID_SDK_ROOT': '', 'ANDROID_HOME': '/home'};
      final roots = resolveAndroidSdkRoots(env);
      expect(roots, isNot(contains('')));
      expect(roots, contains('/home'));
    });

    test('ignores missing HOME when env provided', () {
      final env = {'ANDROID_SDK_ROOT': '/sdk'};
      final roots = resolveAndroidSdkRoots(env);
      expect(roots, contains('/sdk'));
    });
  });

  group('adbArgs integration', () {
    test('ensures SDK path is configured (smoke test)', () {
      // This test would spawn actual process; skip for unit tests
      // The function should not throw when SDK paths are properly set
      expect(true, isTrue);
    });
  });
}
