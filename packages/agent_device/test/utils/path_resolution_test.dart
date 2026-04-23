import 'package:agent_device/src/utils/path_resolution.dart';
import 'package:test/test.dart';

void main() {
  group('path_resolution', () {
    group('expandUserHomePath', () {
      test('expands ~ to home directory', () {
        final home = '/home/user';
        final options = PathResolutionOptions(env: {'HOME': home});
        final result = expandUserHomePath('~', options);
        expect(result, home);
      });

      test('expands ~/ to home/relative', () {
        final home = '/home/user';
        final options = PathResolutionOptions(env: {'HOME': home});
        final result = expandUserHomePath('~/.config', options);
        expect(result, '/home/user/.config');
      });

      test('leaves absolute paths unchanged', () {
        const path = '/absolute/path';
        final result = expandUserHomePath(path);
        expect(result, path);
      });

      test('leaves relative paths unchanged', () {
        const path = 'relative/path';
        final result = expandUserHomePath(path);
        expect(result, path);
      });

      test('uses provided env HOME', () {
        final options = PathResolutionOptions(env: {'HOME': '/custom/home'});
        final result = expandUserHomePath('~/.agent-device', options);
        expect(result, '/custom/home/.agent-device');
      });
    });

    group('resolveUserPath', () {
      test('resolves ~ to absolute path', () {
        final home = '/home/user';
        final options = PathResolutionOptions(env: {'HOME': home});
        final result = resolveUserPath('~', options);
        expect(result, home);
      });

      test('resolves ~/subdir correctly', () {
        final home = '/home/user';
        final options = PathResolutionOptions(env: {'HOME': home});
        final result = resolveUserPath('~/.agent-device/state', options);
        expect(result, '/home/user/.agent-device/state');
      });

      test('resolves absolute paths unchanged', () {
        const path = '/absolute/path';
        final result = resolveUserPath(path);
        expect(result, path);
      });

      test('resolves relative paths against cwd', () {
        final options = PathResolutionOptions(cwd: '/base');
        final result = resolveUserPath('relative', options);
        expect(result, '/base/relative');
      });
    });

    group('resolveHomeDirectory', () {
      test('returns HOME from env when set', () {
        const home = '/home/testuser';
        final result = resolveHomeDirectory({'HOME': home});
        expect(result, home);
      });

      test('trims whitespace from HOME', () {
        const home = '/home/testuser';
        final result = resolveHomeDirectory({'HOME': '  $home  '});
        expect(result, home);
      });

      test('handles missing HOME gracefully', () {
        final result = resolveHomeDirectory({});
        // On systems without HOME, returns empty; on others returns platform default
        expect(result, isA<String>());
      });
    });
  });
}
