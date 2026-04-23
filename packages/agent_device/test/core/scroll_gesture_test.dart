import 'package:agent_device/src/core/scroll_gesture.dart';
import 'package:agent_device/src/utils/errors.dart';
import 'package:test/test.dart';

void main() {
  group('parseScrollDirection', () {
    test('parses valid directions', () {
      expect(parseScrollDirection('up'), ScrollDirection.up);
      expect(parseScrollDirection('down'), ScrollDirection.down);
      expect(parseScrollDirection('left'), ScrollDirection.left);
      expect(parseScrollDirection('right'), ScrollDirection.right);
    });

    test('throws on invalid direction', () {
      expect(
        () => parseScrollDirection('invalid'),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.invalidArgs)
              .having(
                (e) => e.message,
                'message',
                contains('Unknown direction'),
              ),
        ),
      );
    });
  });

  group('buildScrollGesturePlan', () {
    test('builds plan for upward scroll', () {
      final plan = buildScrollGesturePlan(
        const ScrollGestureOptions(
          direction: ScrollDirection.up,
          referenceWidth: 400,
          referenceHeight: 800,
        ),
      );
      expect(plan.direction, ScrollDirection.up);
      expect(plan.x1, 200); // center
      expect(plan.x2, 200); // center
      expect(plan.y1, lessThan(plan.y2)); // y1 < y2 for upward
    });

    test('builds plan for downward scroll', () {
      final plan = buildScrollGesturePlan(
        const ScrollGestureOptions(
          direction: ScrollDirection.down,
          referenceWidth: 400,
          referenceHeight: 800,
        ),
      );
      expect(plan.direction, ScrollDirection.down);
      expect(plan.y1, greaterThan(plan.y2)); // y1 > y2 for downward
    });

    test('builds plan for leftward scroll', () {
      final plan = buildScrollGesturePlan(
        const ScrollGestureOptions(
          direction: ScrollDirection.left,
          referenceWidth: 400,
          referenceHeight: 800,
        ),
      );
      expect(plan.direction, ScrollDirection.left);
      expect(plan.x1, lessThan(plan.x2)); // x1 < x2 for leftward
    });

    test('builds plan for rightward scroll', () {
      final plan = buildScrollGesturePlan(
        const ScrollGestureOptions(
          direction: ScrollDirection.right,
          referenceWidth: 400,
          referenceHeight: 800,
        ),
      );
      expect(plan.direction, ScrollDirection.right);
      expect(plan.x1, greaterThan(plan.x2)); // x1 > x2 for rightward
    });

    test('respects custom pixel amount', () {
      final plan = buildScrollGesturePlan(
        const ScrollGestureOptions(
          direction: ScrollDirection.up,
          pixels: 200,
          referenceWidth: 400,
          referenceHeight: 800,
        ),
      );
      expect(plan.pixels, 200);
    });

    test('respects custom fractional amount', () {
      final plan = buildScrollGesturePlan(
        const ScrollGestureOptions(
          direction: ScrollDirection.down,
          amount: 0.5,
          referenceWidth: 400,
          referenceHeight: 800,
        ),
      );
      expect(plan.amount, 0.5);
      expect(plan.pixels, greaterThan(0));
    });

    test('clamps pixels to max travel distance', () {
      final plan = buildScrollGesturePlan(
        const ScrollGestureOptions(
          direction: ScrollDirection.up,
          pixels: 10000, // way too large
          referenceWidth: 400,
          referenceHeight: 800,
        ),
      );
      expect(plan.pixels, lessThan(800)); // height limited
    });

    test('throws on invalid amount', () {
      expect(
        () => buildScrollGesturePlan(
          const ScrollGestureOptions(
            direction: ScrollDirection.up,
            amount: -0.5,
            referenceWidth: 400,
            referenceHeight: 800,
          ),
        ),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.invalidArgs)
              .having((e) => e.message, 'message', contains('positive number')),
        ),
      );
    });

    test('throws on invalid pixels', () {
      expect(
        () => buildScrollGesturePlan(
          const ScrollGestureOptions(
            direction: ScrollDirection.up,
            pixels: -100,
            referenceWidth: 400,
            referenceHeight: 800,
          ),
        ),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppErrorCodes.invalidArgs)
              .having(
                (e) => e.message,
                'message',
                contains('positive integer'),
              ),
        ),
      );
    });
  });
}
