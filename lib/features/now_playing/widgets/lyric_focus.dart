import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A gentle, consistent focus effect: active and manually browsed lines stay
/// sharp. Distant lines use the same small blur instead of becoming sharper.
class LyricFocus extends StatelessWidget {
  const LyricFocus({
    super.key,
    required this.isActive,
    required this.isBrowsing,
    required this.child,
  });

  final bool isActive;
  final bool isBrowsing;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: isActive || isBrowsing ? 0 : 0.65),
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOut,
    child: child,
    builder: (context, sigma, child) => ImageFiltered(
      enabled: !isActive && !isBrowsing && sigma > 0.01,
      imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    ),
  );
}
