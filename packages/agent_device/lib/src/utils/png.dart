/// Port of `agent-device/src/utils/png.ts`.
///
/// PNG image loading and decoding with optional resizing.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'errors.dart';

/// Decode a PNG from a buffer.
///
/// Throws [AppError] with code 'COMMAND_FAILED' if decoding fails.
img.Image decodePng(List<int> buffer, String label) {
  try {
    final image = img.decodePng(Uint8List.fromList(buffer));
    if (image == null) {
      throw AppError(
        AppErrorCodes.commandFailed,
        'Failed to decode $label as PNG (decodePng returned null)',
        details: {'label': label},
      );
    }
    return image;
  } catch (e) {
    throw AppError(
      AppErrorCodes.commandFailed,
      'Failed to decode $label as PNG',
      details: {
        'label': label,
        'reason': e is Exception ? e.toString() : 'Unknown error',
      },
      cause: e,
    );
  }
}

/// Resize a PNG file to fit within a maximum dimension.
///
/// If the image already fits, does nothing. Otherwise, scales it down
/// proportionally to fit within [maxSize] on the longest edge.
///
/// Throws [AppError] if:
/// - [maxSize] is not a positive integer
/// - The file cannot be read or written
/// - PNG decoding/encoding fails
Future<void> resizePngFileToMaxSize(String filePath, int maxSize) async {
  if (maxSize < 1) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'Screenshot max size must be a positive integer',
    );
  }

  final file = File(filePath);
  final buffer = await file.readAsBytes();
  final source = decodePng(buffer, 'screenshot');

  final longestEdge = (source.width > source.height)
      ? source.width
      : source.height;

  if (longestEdge <= maxSize) {
    return;
  }

  final scale = maxSize / longestEdge;
  final newWidth = ((source.width * scale).round())
      .clamp(1, double.infinity)
      .toInt();
  final newHeight = ((source.height * scale).round())
      .clamp(1, double.infinity)
      .toInt();
  final resized = _resizePngBox(source, newWidth, newHeight);

  final encodedBytes = img.encodePng(resized);
  await file.writeAsBytes(encodedBytes);
}

// ============================================================================
// Private helpers
// ============================================================================

/// Resize a PNG using a box-filter resampling algorithm.
///
/// Averages pixel values across source regions that map to each destination
/// pixel, producing a smooth downscaled result.
img.Image _resizePngBox(img.Image source, int width, int height) {
  final output = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    final sourceTop = (y * source.height) / height;
    final sourceBottom = ((y + 1) * source.height) / height;

    for (int x = 0; x < width; x++) {
      final sourceLeft = (x * source.width) / width;
      final sourceRight = ((x + 1) * source.width) / width;

      double red = 0;
      double green = 0;
      double blue = 0;
      double alpha = 0;
      double weight = 0;

      for (
        int sourceY = sourceTop.floor();
        sourceY < sourceBottom.ceil();
        sourceY++
      ) {
        final yWeight =
            (sourceY + 1).clamp(sourceTop, sourceBottom) -
            sourceY.clamp(sourceTop, sourceBottom);

        for (
          int sourceX = sourceLeft.floor();
          sourceX < sourceRight.ceil();
          sourceX++
        ) {
          final pixelWeight =
              yWeight *
              ((sourceX + 1).clamp(sourceLeft, sourceRight) -
                  sourceX.clamp(sourceLeft, sourceRight));

          final sourcePixel = source.getPixelSafe(sourceX, sourceY);
          red += sourcePixel.r * pixelWeight;
          green += sourcePixel.g * pixelWeight;
          blue += sourcePixel.b * pixelWeight;
          alpha += sourcePixel.a * pixelWeight;
          weight += pixelWeight;
        }
      }

      if (weight > 0) {
        final r = (red / weight).round().clamp(0, 255).toInt();
        final g = (green / weight).round().clamp(0, 255).toInt();
        final b = (blue / weight).round().clamp(0, 255).toInt();
        final a = (alpha / weight).round().clamp(0, 255).toInt();
        output.setPixelRgba(x, y, r, g, b, a);
      }
    }
  }

  return output;
}
