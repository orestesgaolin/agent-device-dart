import 'dart:io';
import 'dart:typed_data';
import 'package:agent_device/src/utils/errors.dart';
import 'package:agent_device/src/utils/png.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  group('png', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('png_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('decodePng', () {
      test('decodes a valid PNG buffer', () {
        // Create a small 4x4 PNG
        final image = img.Image(width: 4, height: 4);
        final encoded = img.encodePng(image);
        final decoded = decodePng(encoded, 'test');

        expect(decoded, isNotNull);
        expect(decoded.width, equals(4));
        expect(decoded.height, equals(4));
      });

      test('throws on invalid PNG data', () {
        final invalidData = Uint8List.fromList([0xFF, 0xFF, 0xFF]);
        expect(
          () => decodePng(invalidData, 'invalid'),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.commandFailed),
            ),
          ),
        );
      });

      test('includes label in error details', () {
        final invalidData = Uint8List.fromList([0xFF, 0xFF, 0xFF]);
        try {
          decodePng(invalidData, 'test-label');
          fail('should throw');
        } on AppError catch (e) {
          expect(e.details?['label'], equals('test-label'));
        }
      });

      test('preserves image pixel data', () {
        // Create a 2x2 image with specific colors
        final image = img.Image(width: 2, height: 2);
        // Set pixels
        image.setPixelRgba(0, 0, 255, 0, 0, 255); // Red
        image.setPixelRgba(1, 0, 0, 255, 0, 255); // Green
        image.setPixelRgba(0, 1, 0, 0, 255, 255); // Blue
        image.setPixelRgba(1, 1, 255, 255, 255, 255); // White

        final encoded = img.encodePng(image);
        final decoded = decodePng(encoded, 'test');

        // Verify dimensions
        expect(decoded.width, equals(2));
        expect(decoded.height, equals(2));
      });
    });

    group('resizePngFileToMaxSize', () {
      test('resizes a PNG that exceeds maxSize', () async {
        // Create a 100x100 image
        final image = img.Image(width: 100, height: 100);
        final encoded = img.encodePng(image);

        final filePath = '${tempDir.path}/test.png';
        final file = File(filePath);
        await file.writeAsBytes(encoded);

        // Resize to max 50 on longest edge
        await resizePngFileToMaxSize(filePath, 50);

        // Verify file was resized
        final resized = decodePng(await file.readAsBytes(), 'resized');
        expect(resized.width, lessThanOrEqualTo(50));
        expect(resized.height, lessThanOrEqualTo(50));
      });

      test('does not resize PNG that fits within maxSize', () async {
        // Create a 30x30 image
        final image = img.Image(width: 30, height: 30);
        final encoded = img.encodePng(image);

        final filePath = '${tempDir.path}/test.png';
        final file = File(filePath);
        await file.writeAsBytes(encoded);

        // Resize to max 100 (should not change)
        await resizePngFileToMaxSize(filePath, 100);

        final resized = decodePng(await file.readAsBytes(), 'resized');
        expect(resized.width, equals(30));
        expect(resized.height, equals(30));
      });

      test('throws on invalid maxSize', () async {
        final image = img.Image(width: 100, height: 100);
        final encoded = img.encodePng(image);

        final filePath = '${tempDir.path}/test.png';
        await File(filePath).writeAsBytes(encoded);

        expect(
          () => resizePngFileToMaxSize(filePath, 0),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.invalidArgs),
            ),
          ),
        );
      });

      test('throws on negative maxSize', () async {
        final image = img.Image(width: 100, height: 100);
        final encoded = img.encodePng(image);

        final filePath = '${tempDir.path}/test.png';
        await File(filePath).writeAsBytes(encoded);

        expect(
          () => resizePngFileToMaxSize(filePath, -1),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.invalidArgs),
            ),
          ),
        );
      });

      test('throws if file does not exist', () async {
        final filePath = '${tempDir.path}/nonexistent.png';
        expect(
          () => resizePngFileToMaxSize(filePath, 50),
          throwsA(isA<Object>()),
        );
      });

      test('throws if file is not a valid PNG', () async {
        final filePath = '${tempDir.path}/invalid.png';
        await File(filePath).writeAsString('not a png');

        expect(
          () => resizePngFileToMaxSize(filePath, 50),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              equals(AppErrorCodes.commandFailed),
            ),
          ),
        );
      });

      test('maintains aspect ratio when resizing', () async {
        // Create a 200x100 image (2:1 aspect ratio)
        final image = img.Image(width: 200, height: 100);
        final encoded = img.encodePng(image);

        final filePath = '${tempDir.path}/test.png';
        final file = File(filePath);
        await file.writeAsBytes(encoded);

        // Resize to max 50
        await resizePngFileToMaxSize(filePath, 50);

        final resized = decodePng(await file.readAsBytes(), 'resized');

        // Longest edge is 200, scale to 50: 50/200 = 0.25
        // 200 * 0.25 = 50, 100 * 0.25 = 25
        expect(resized.width, equals(50));
        expect(resized.height, equals(25));
      });

      test('produces a valid PNG after resize', () async {
        final image = img.Image(width: 100, height: 100);
        final encoded = img.encodePng(image);

        final filePath = '${tempDir.path}/test.png';
        final file = File(filePath);
        await file.writeAsBytes(encoded);

        await resizePngFileToMaxSize(filePath, 50);

        // Should be able to read and decode the resized file
        final resized = decodePng(await file.readAsBytes(), 'resized');

        expect(resized.width, equals(50));
        expect(resized.height, equals(50));
      });
    });

    group('edge cases', () {
      test('handles 1x1 PNG', () {
        final image = img.Image(width: 1, height: 1);
        final encoded = img.encodePng(image);
        final decoded = decodePng(encoded, 'tiny');
        expect(decoded.width, equals(1));
        expect(decoded.height, equals(1));
      });

      test('handles very large maxSize', () async {
        final image = img.Image(width: 10, height: 10);
        final encoded = img.encodePng(image);

        final filePath = '${tempDir.path}/test.png';
        await File(filePath).writeAsBytes(encoded);

        // Should not throw or resize
        await resizePngFileToMaxSize(filePath, 10000);

        final resized = decodePng(
          await File(filePath).readAsBytes(),
          'resized',
        );
        expect(resized.width, equals(10));
        expect(resized.height, equals(10));
      });
    });
  });
}
