import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

/// A slowly moving wash of the colors in the current album art.
class FluidArtBackground extends StatefulWidget {
  final String? thumbnailPath;
  final bool isOnDevice;

  const FluidArtBackground({
    super.key,
    required this.thumbnailPath,
    this.isOnDevice = true,
  });

  @override
  State<FluidArtBackground> createState() => _FluidArtBackgroundState();
}

class _FluidArtBackgroundState extends State<FluidArtBackground>
    with SingleTickerProviderStateMixin {
  static const Color _fallback = Color(0xFF2A2A2E);

  /// The art is heavily blurred, so a tiny decode is enough.
  static const int _decodeWidth = 64;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRect(
        child: ColoredBox(
          color: _fallback,
          // Cross-fades to the new colors when the song changes.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: _buildArt(),
          ),
        ),
      ),
    );
  }

  Widget _buildArt() {
    final String? path = widget.thumbnailPath;
    if (path == null) {
      return const SizedBox.expand();
    }

    final ImageProvider image = ResizeImage(
      widget.isOnDevice
          ? FileImage(File(path))
          : NetworkImage(path),
      width: _decodeWidth,
    );

    return Stack(
      key: ValueKey(path),
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: 36,
            sigmaY: 36,
            tileMode: TileMode.clamp,
          ),
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(_saturation),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Base layer, then two patches turning at different speeds.
                _buildLayer(image, Alignment.center, 1.5, 1, isCircle: false),
                _buildLayer(image, Alignment.topLeft, 0.8, -2),
                _buildLayer(image, Alignment.bottomRight, 0.7, 3),
              ],
            ),
          ),
        ),
        // Keeps white text readable on bright artwork.
        const ColoredBox(color: Color(0x73000000)),
      ],
    );
  }

  /// A copy of the art covering [size] times the longer side.
  ///
  /// [turns] is a whole number so the animation repeats without a jump.
  Widget _buildLayer(
    ImageProvider image,
    Alignment alignment,
    double size,
    int turns, {
    bool isCircle = true,
  }) {
    final Widget art = Image(
      image: image,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final double side = constraints.biggest.longestSide * size;

        return OverflowBox(
          alignment: alignment,
          minWidth: side,
          maxWidth: side,
          minHeight: side,
          maxHeight: side,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.rotate(
              angle: _controller.value * turns * 2 * math.pi,
              child: child,
            ),
            child: isCircle ? ClipOval(child: art) : art,
          ),
        );
      },
    );
  }
}

/// Boosts saturation by 1.6 so blurred colors do not turn muddy.
const List<double> _saturation = <double>[
  1.4724, -0.4291, -0.0433, 0, 0, //
  -0.1276, 1.1709, -0.0433, 0, 0, //
  -0.1276, -0.4291, 1.5567, 0, 0, //
  0, 0, 0, 1, 0, //
];
