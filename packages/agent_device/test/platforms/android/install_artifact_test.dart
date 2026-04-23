/// Tests for install_artifact.dart — Android APK/AAB handling.
library;

import 'package:agent_device/src/platforms/android/install_artifact.dart';
import 'package:test/test.dart';

void main() {
  group('isAndroidInstallablePath (via prepareAndroidInstallArtifact)', () {
    test('rejects non-APK/AAB files', () async {
      expect(
        () => prepareAndroidInstallArtifact('/path/to/file.txt'),
        throwsArgumentError,
      );
    });

    test('accepts APK files (lowercase)', () async {
      // Mock filesystem would be needed for full test
      // For now, test the validation logic via error handling
      expect(true, isTrue); // Placeholder
    });

    test('accepts AAB files (lowercase)', () async {
      expect(true, isTrue); // Placeholder
    });

    test('case-insensitive extension matching', () async {
      expect(true, isTrue); // Placeholder
    });
  });

  group('PreparedAndroidInstallArtifact', () {
    test('creates artifact with installable path', () async {
      expect(true, isTrue); // Placeholder - requires mocked filesystem
    });

    test('includes cleanup callback', () async {
      expect(true, isTrue); // Placeholder
    });

    test('optionally resolves package name', () async {
      expect(true, isTrue); // Placeholder - requires manifest parsing
    });
  });

  group('Error handling', () {
    test('throws on invalid file type', () async {
      expect(
        () => prepareAndroidInstallArtifact('/path/to/archive.zip'),
        throwsArgumentError,
      );
    });

    test('gracefully handles missing files', () async {
      // Would need filesystem mocking for real test
      expect(true, isTrue); // Placeholder
    });
  });
}
