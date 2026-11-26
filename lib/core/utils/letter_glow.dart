import 'dart:math' as math;

/// Glow of letter [index] out of [count] when a held word is [progress]
/// sung. Both values run from 0 to 1. The glow travels from the first letter
/// to the last, overlapping neighbours.
double letterGlowStrength(double progress, int index, int count) {
  const double spread = 3;
  final double head = progress * (count - 1 + spread);
  final double local = (head - index) / spread;
  if (local <= 0 || local >= 1) {
    return 0;
  }
  return math.sin(math.pi * local);
}
