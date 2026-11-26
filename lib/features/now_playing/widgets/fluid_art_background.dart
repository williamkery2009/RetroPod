import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

/// A slowly moving wash of the colors in the current album art.
///
/// The art is blurred once per song. Each animation frame only moves the
/// finished images, which is far cheaper than blurring every frame.
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
    final String? path = widget.thumbnailPath;

    return RepaintBoundary(
      child: ClipRect(
        child: ColoredBox(
          color: _fallback,
          // Cross-fades to the new colors when the song changes.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: path == null
                ? const SizedBox.expand()
                : _ArtWash(
                    key: ValueKey(path),
                    path: path,
                    isOnDevice: widget.isOnDevice,
                    animation: _controller,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Blurs one cover and owns the resulting images, so that they stay alive
/// while it fades out.
class _ArtWash extends StatefulWidget {
  final String path;
  final bool isOnDevice;
  final Animation<double> animation;

  const _ArtWash({
    super.key,
    required this.path,
    required this.isOnDevice,
    required this.animation,
  });

  @override
  State<_ArtWash> createState() => _ArtWashState();
}

class _ArtWashState extends State<_ArtWash> {
  /// Side of the blurred images. Soft colors need very few pixels.
  static const int _side = 128;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _base;
  ui.Image? _patch;

  @override
  void initState() {
    super.initState();
    final ImageProvider provider = widget.isOnDevice
        ? FileImage(File(widget.path))
        : NetworkImage(widget.path);

    _listener = ImageStreamListener((info, _) {
      final ui.Image source = info.image.clone();
      info.dispose();
      _stopListening();
      unawaited(_bakeImages(source));
    }, onError: (_, _) => _stopListening());

    final ImageStream stream = ResizeImage(
      provider,
      width: _side,
    ).resolve(ImageConfiguration.empty);
    _stream = stream;
    stream.addListener(_listener!);
  }

  void _stopListening() {
    final ImageStreamListener? listener = _listener;
    if (listener != null) {
      _listener = null;
      _stream?.removeListener(listener);
    }
  }

  Future<void> _bakeImages(ui.Image source) async {
    final ui.Image base = await _bake(source, isFeathered: false);
    final ui.Image patch = await _bake(source, isFeathered: true);
    source.dispose();

    if (!mounted) {
      base.dispose();
      patch.dispose();
      return;
    }
    setState(() {
      _base = base;
      _patch = patch;
    });
  }

  /// Draws a blurred, more saturated copy of [source]. A feathered copy
  /// fades out toward a circular edge.
  Future<ui.Image> _bake(ui.Image source, {required bool isFeathered}) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Rect bounds = Offset.zero & const Size.square(_side + 0.0);

    canvas
      ..saveLayer(bounds, Paint())
      ..saveLayer(
        null,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      );

    final double crop = math.min(source.width, source.height).toDouble();
    canvas
      ..drawImageRect(
        source,
        Rect.fromCenter(
          center: Offset(source.width / 2, source.height / 2),
          width: crop,
          height: crop,
        ),
        // Overdraws so the blur does not fade the edges.
        bounds.inflate(32),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = const ColorFilter.matrix(_saturation),
      )
      ..restore();

    if (isFeathered) {
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.radial(
            bounds.center,
            _side / 2,
            const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
            const [0.3, 1],
          ),
      );
    }
    canvas.restore();

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(_side, _side);
    picture.dispose();
    return image;
  }

  @override
  void dispose() {
    _stopListening();
    _base?.dispose();
    _patch?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? base = _base;
    final ui.Image? patch = _patch;
    if (base == null || patch == null) {
      return const SizedBox.expand();
    }

    return CustomPaint(
      painter: _WashPainter(
        base: base,
        patch: patch,
        animation: widget.animation,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _WashPainter extends CustomPainter {
  final ui.Image base;
  final ui.Image patch;
  final Animation<double> animation;

  _WashPainter({
    required this.base,
    required this.patch,
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final double diagonal = Offset(size.width, size.height).distance;

    // The base covers the corners at every angle.
    _draw(canvas, base, size.center(Offset.zero), diagonal, 1);
    _draw(
      canvas,
      patch,
      Offset(size.width * 0.25, size.height * 0.3),
      size.longestSide,
      -2,
    );
    _draw(
      canvas,
      patch,
      Offset(size.width * 0.8, size.height * 0.75),
      size.longestSide * 0.85,
      3,
    );

    // Keeps white text readable on bright artwork.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x73000000),
    );
  }

  /// [turns] is a whole number so the animation repeats without a jump.
  void _draw(
    Canvas canvas,
    ui.Image image,
    Offset center,
    double side,
    int turns,
  ) {
    final double angle = animation.value * turns * 2 * math.pi;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(angle)
      // Off-center, so each copy also drifts as it turns.
      ..drawImageRect(
        image,
        Offset.zero & Size(image.width + 0.0, image.height + 0.0),
        Rect.fromCenter(
          center: turns == 1 ? Offset.zero : Offset(side * 0.15, 0),
          width: side,
          height: side,
        ),
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_WashPainter oldDelegate) {
    return oldDelegate.base != base ||
        oldDelegate.patch != patch ||
        oldDelegate.animation != animation;
  }
}

/// Boosts saturation by 1.6 so blurred colors do not turn muddy.
const List<double> _saturation = <double>[
  1.4724, -0.4291, -0.0433, 0, 0, //
  -0.1276, 1.1709, -0.0433, 0, 0, //
  -0.1276, -0.4291, 1.5567, 0, 0, //
  0, 0, 0, 1, 0, //
];
