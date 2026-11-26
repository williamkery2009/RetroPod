import 'package:flutter_test/flutter_test.dart';
import 'package:retropod/core/utils/scroll_accelerator.dart';

void main() {
  final DateTime start = DateTime(2026);

  List<int> spin(
    ScrollAccelerator accelerator, {
    required int steps,
    int gapMilliseconds = 80,
    int listLength = 100,
  }) {
    return [
      for (int i = 0; i < steps; i++)
        accelerator.stepSize(
          now: start.add(Duration(milliseconds: i * gapMilliseconds)),
          isForward: true,
          listLength: listLength,
        ),
    ];
  }

  group('ScrollAccelerator', () {
    test('speeds up during a long fast spin', () {
      final steps = spin(ScrollAccelerator(), steps: 25);
      expect(steps.first, 1);
      expect(steps[8], 2);
      expect(steps.last, 5);
    });

    test('stays at one step when turning slowly', () {
      final steps = spin(
        ScrollAccelerator(),
        steps: 25,
        gapMilliseconds: 400,
      );
      expect(steps.every((step) => step == 1), isTrue);
    });

    test('stays at one step in short lists', () {
      final steps = spin(ScrollAccelerator(), steps: 25, listLength: 10);
      expect(steps.every((step) => step == 1), isTrue);
    });

    test('resets when the direction changes', () {
      final accelerator = ScrollAccelerator();
      spin(accelerator, steps: 25);
      expect(
        accelerator.stepSize(
          now: start.add(const Duration(milliseconds: 25 * 80)),
          isForward: false,
          listLength: 100,
        ),
        1,
      );
    });
  });

  group('indexLetter', () {
    test('uses the upper case first letter', () {
      expect(indexLetter(' blue'), 'B');
    });

    test('groups digits, symbols and empty titles', () {
      expect(indexLetter('7 rings'), '#');
      expect(indexLetter('(intro)'), '#');
      expect(indexLetter(''), '#');
    });
  });
}
