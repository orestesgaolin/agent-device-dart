// Port of agent-device/src/core/scroll-gesture.ts

import '../utils/errors.dart';

enum ScrollDirection {
  up('up'),
  down('down'),
  left('left'),
  right('right');

  final String value;

  const ScrollDirection(this.value);

  @override
  String toString() => value;
}

/// Options for building a scroll gesture plan.
class ScrollGestureOptions {
  final ScrollDirection direction;
  final double? amount;
  final double? pixels;
  final int referenceWidth;
  final int referenceHeight;

  const ScrollGestureOptions({
    required this.direction,
    this.amount,
    this.pixels,
    required this.referenceWidth,
    required this.referenceHeight,
  });
}

/// Calculated scroll gesture plan with coordinates and distance.
class ScrollGesturePlan {
  final ScrollDirection direction;
  final int x1;
  final int y1;
  final int x2;
  final int y2;
  final int referenceWidth;
  final int referenceHeight;
  final double? amount;
  final int pixels;

  const ScrollGesturePlan({
    required this.direction,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.referenceWidth,
    required this.referenceHeight,
    this.amount,
    required this.pixels,
  });
}

const double _defaultScrollAmount = 0.6;
const double _defaultEdgePaddingFraction = 0.05;

/// Builds a scroll gesture plan from the given options.
ScrollGesturePlan buildScrollGesturePlan(ScrollGestureOptions options) {
  final direction = options.direction;
  final axisLength =
      (direction == ScrollDirection.up || direction == ScrollDirection.down)
      ? options.referenceHeight
      : options.referenceWidth;

  final requestedAmount = _resolveRequestedAmount(options.amount);
  final requestedPixels = options.pixels != null
      ? _normalizeRequestedPixels(options.pixels!)
      : (axisLength * requestedAmount).round();

  final edgePadding = ((axisLength * _defaultEdgePaddingFraction).round())
      .clamp(1, double.infinity)
      .toInt();
  final maxTravelPixels = (axisLength - edgePadding * 2)
      .clamp(1, double.infinity)
      .toInt();
  final travelPixels = requestedPixels.clamp(1, maxTravelPixels);
  final halfTravel = (travelPixels / 2).round();

  final centerX = (options.referenceWidth / 2).round();
  final centerY = (options.referenceHeight / 2).round();

  switch (direction) {
    case ScrollDirection.up:
      return ScrollGesturePlan(
        direction: direction,
        x1: centerX,
        y1: centerY - halfTravel,
        x2: centerX,
        y2: centerY + halfTravel,
        referenceWidth: options.referenceWidth,
        referenceHeight: options.referenceHeight,
        amount: options.amount,
        pixels: travelPixels,
      );
    case ScrollDirection.down:
      return ScrollGesturePlan(
        direction: direction,
        x1: centerX,
        y1: centerY + halfTravel,
        x2: centerX,
        y2: centerY - halfTravel,
        referenceWidth: options.referenceWidth,
        referenceHeight: options.referenceHeight,
        amount: options.amount,
        pixels: travelPixels,
      );
    case ScrollDirection.left:
      return ScrollGesturePlan(
        direction: direction,
        x1: centerX - halfTravel,
        y1: centerY,
        x2: centerX + halfTravel,
        y2: centerY,
        referenceWidth: options.referenceWidth,
        referenceHeight: options.referenceHeight,
        amount: options.amount,
        pixels: travelPixels,
      );
    case ScrollDirection.right:
      return ScrollGesturePlan(
        direction: direction,
        x1: centerX + halfTravel,
        y1: centerY,
        x2: centerX - halfTravel,
        y2: centerY,
        referenceWidth: options.referenceWidth,
        referenceHeight: options.referenceHeight,
        amount: options.amount,
        pixels: travelPixels,
      );
  }
}

/// Parses a scroll direction string.
ScrollDirection parseScrollDirection(String direction) {
  return switch (direction) {
    'up' => ScrollDirection.up,
    'down' => ScrollDirection.down,
    'left' => ScrollDirection.left,
    'right' => ScrollDirection.right,
    _ => throw AppError(
      AppErrorCodes.invalidArgs,
      'Unknown direction: $direction',
    ),
  };
}

double _resolveRequestedAmount(double? amount) {
  if (amount == null) return _defaultScrollAmount;
  if (!amount.isFinite || amount <= 0) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'scroll amount must be a positive number',
    );
  }
  return amount;
}

int _normalizeRequestedPixels(double pixels) {
  if (!pixels.isFinite || pixels <= 0) {
    throw AppError(
      AppErrorCodes.invalidArgs,
      'scroll pixels must be a positive integer',
    );
  }
  return (pixels.round()).clamp(1, double.infinity).toInt();
}
