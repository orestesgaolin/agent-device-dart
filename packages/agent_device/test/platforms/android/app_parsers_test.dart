/// Tests for app_parsers.dart — Android package and app parsing.
library;

import 'package:agent_device/src/platforms/android/app_parsers.dart';
import 'package:test/test.dart';

void main() {
  group('parseAndroidLaunchablePackages', () {
    test('parses standard pm list output (with package: prefix)', () {
      const stdout = '''
package:com.google.android.apps.maps
package:com.android.chrome
package:com.example.myapp
''';
      final packages = parseAndroidLaunchablePackages(stdout);
      // Note: parseAndroidLaunchablePackages does NOT strip "package:" prefix
      // It extracts the first token, which includes the prefix
      expect(
        packages,
        containsAll([
          'package:com.google.android.apps.maps',
          'package:com.android.chrome',
          'package:com.example.myapp',
        ]),
      );
    });

    test('extracts package from component reference', () {
      const stdout = 'com.example.app/com.example.app.MainActivity';
      final packages = parseAndroidLaunchablePackages(stdout);
      expect(packages, contains('com.example.app'));
    });

    test('handles leading/trailing whitespace', () {
      const stdout = '''
  package:com.app1
  package:com.app2
  ''';
      final packages = parseAndroidLaunchablePackages(stdout);
      expect(packages, containsAll(['package:com.app1', 'package:com.app2']));
    });

    test('ignores empty lines', () {
      const stdout = '''
package:com.app1


package:com.app2
''';
      final packages = parseAndroidLaunchablePackages(stdout);
      expect(packages, equals(['package:com.app1', 'package:com.app2']));
    });

    test('deduplicates package names', () {
      const stdout = '''
package:com.app1
package:com.app1
package:com.app2
''';
      final packages = parseAndroidLaunchablePackages(stdout);
      expect(packages.where((p) => p == 'package:com.app1').length, equals(1));
    });
  });

  group('parseAndroidUserInstalledPackages', () {
    test('strips "package:" prefix', () {
      const stdout = '''
package:com.app1
package:com.app2
''';
      final packages = parseAndroidUserInstalledPackages(stdout);
      expect(packages, equals(['com.app1', 'com.app2']));
    });

    test('handles bare package names', () {
      const stdout = '''
com.app1
com.app2
''';
      final packages = parseAndroidUserInstalledPackages(stdout);
      expect(packages, equals(['com.app1', 'com.app2']));
    });

    test('filters out empty lines', () {
      const stdout = '''
package:com.app1

package:com.app2

''';
      final packages = parseAndroidUserInstalledPackages(stdout);
      expect(packages, equals(['com.app1', 'com.app2']));
    });

    test('preserves order', () {
      const stdout = '''
package:z.app
package:a.app
package:m.app
''';
      final packages = parseAndroidUserInstalledPackages(stdout);
      expect(packages, equals(['z.app', 'a.app', 'm.app']));
    });
  });

  group('parseAndroidForegroundApp', () {
    test('extracts package and activity from mCurrentFocus', () {
      const text = '''
mCurrentFocus=Window{ad26e49 u0 com.android.systemui/com.android.systemui.statusbar.phone.PhoneStatusBarView}
''';
      final app = parseAndroidForegroundApp(text);
      expect(app?.package, equals('com.android.systemui'));
      expect(
        app?.activity,
        equals('com.android.systemui.statusbar.phone.PhoneStatusBarView'),
      );
    });

    test('extracts from mFocusedApp', () {
      const text = '''
mFocusedApp=AppWindowToken{c8d1c4c token=Token{6f17acd ActivityRecord{f04b5c0 u0 com.example.app/.MainActivity t1}}}
''';
      final app = parseAndroidForegroundApp(text);
      expect(app?.package, equals('com.example.app'));
    });

    test('extracts from mResumedActivity', () {
      const text =
          'mResumedActivity: ActivityRecord{a1b2c3d u0 com.google.android.gms/.MainActivity t42}';
      final app = parseAndroidForegroundApp(text);
      expect(app?.package, equals('com.google.android.gms'));
    });

    test('extracts from ResumedActivity', () {
      const text =
          r'ResumedActivity: com.example.test/com.example.test.LaunchActivity';
      final app = parseAndroidForegroundApp(text);
      expect(app?.package, equals('com.example.test'));
      expect(app?.activity, equals('com.example.test.LaunchActivity'));
    });

    test('handles activity names with inner classes', () {
      const text =
          r'mCurrentFocus=Window{... com.app/com.app.Outer$InnerActivity ...}';
      final app = parseAndroidForegroundApp(text);
      expect(app?.package, equals('com.app'));
      expect(app?.activity, contains('InnerActivity'));
    });

    test('returns null for no match', () {
      const text = 'some random output with no focus info';
      final app = parseAndroidForegroundApp(text);
      expect(app, isNull);
    });

    test('handles malformed component names gracefully', () {
      const text = 'mCurrentFocus=Window{invalid-package/no-slash}';
      final app = parseAndroidForegroundApp(text);
      expect(app, isNull);
    });
  });
}
