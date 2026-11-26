import 'package:flutter_test/flutter_test.dart';
import 'package:retropod/core/utils/letter_glow.dart';

void main() {
  group('letterGlowStrength', () {
    test('is dark before and after the word', () {
      for (int i = 0; i < 5; i++) {
        expect(letterGlowStrength(0, i, 5), 0);
        expect(letterGlowStrength(1, i, 5), 0);
      }
    });

    test('moves from the first letter to the last', () {
      expect(
        letterGlowStrength(0.2, 0, 5),
        greaterThan(letterGlowStrength(0.2, 4, 5)),
      );
      expect(
        letterGlowStrength(0.8, 4, 5),
        greaterThan(letterGlowStrength(0.8, 0, 5)),
      );
    });
  });
}
