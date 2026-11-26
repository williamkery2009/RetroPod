import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:retropod/core/models/lrc_lyrics.dart';
import 'package:retropod/core/utils/letter_glow.dart';

/// Paints a lyric line that fills word by word as [position] advances.
class KaraokeLine extends StatelessWidget {
  final List<LrcWord> words;
  final ValueListenable<Duration> position;
  final TextStyle style;
  final TextAlign textAlign;

  const KaraokeLine({
    super.key,
    required this.words,
    required this.position,
    required this.style,
    required this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle baseStyle = DefaultTextStyle.of(context).style.merge(style);
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final TextDirection textDirection = Directionality.of(context);

    // Joined words match LrcLine.text apart from outer whitespace, and keep
    // the character offsets used by the painter exact.
    final String text = words.map((word) => word.text).join().trimRight();

    return LayoutBuilder(
      builder: (context, constraints) {
        final TextPainter sizer = TextPainter(
          text: TextSpan(text: text, style: baseStyle),
          textAlign: textAlign,
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
        );
        final Size size = sizer.size;
        sizer.dispose();

        return Semantics(
          label: text,
          child: CustomPaint(
            size: size,
            painter: _KaraokePainter(
              words: words,
              text: text,
              position: position,
              style: baseStyle,
              textAlign: textAlign,
              textDirection: textDirection,
              textScaler: textScaler,
            ),
          ),
        );
      },
    );
  }
}

class _KaraokePainter extends CustomPainter {
  /// Height a sung word rises by, in logical pixels.
  static const double _lift = 1.5;

  /// Width of the soft edge at the front of the fill.
  static const double _edge = 12;

  /// Words held at least this long glow while sung.
  static const Duration _longWord = Duration(milliseconds: 1000);

  static const double _dimOpacity = 0.35;

  final List<LrcWord> words;
  final String text;
  final ValueListenable<Duration> position;
  final TextStyle style;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;

  _KaraokePainter({
    required this.words,
    required this.text,
    required this.position,
    required this.style,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
  }) : super(repaint: position);

  TextPainter _layout(Color color, double width) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(color: color),
      ),
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(minWidth: width, maxWidth: width);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Color color = style.color ?? CupertinoColors.white;
    final TextPainter dim = _layout(
      color.withValues(alpha: _dimOpacity),
      size.width,
    );
    final TextPainter bright = _layout(color, size.width);
    final Duration now = position.value;

    int offset = 0;
    for (final LrcWord word in words) {
      final int start = math.min(offset, text.length);
      final int end = math.min(offset + word.text.length, text.length);
      offset += word.text.length;
      if (start == end) {
        continue;
      }

      // A word wrapped across rows has one box per row.
      final List<TextBox> boxes = dim.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      if (boxes.isEmpty) {
        continue;
      }

      final double progress = word.progressAt(now);
      final double rise = _lift * Curves.easeOut.transform(progress);
      final double totalWidth = boxes.fold(
        0,
        (sum, box) => sum + box.right - box.left,
      );
      double filled = totalWidth * progress;

      for (final TextBox box in boxes) {
        final Rect rect = box.toRect();
        final bool isRtl = box.direction == TextDirection.rtl;

        canvas
          ..save()
          ..translate(0, -rise)
          ..clipRect(rect);
        dim.paint(canvas, Offset.zero);

        if (progress >= 1) {
          bright.paint(canvas, Offset.zero);
        } else if (filled > 0) {
          // The soft edge starts off the word and has left it when full.
          final double front =
              math.min(filled / rect.width, 1.0) * (rect.width + _edge);
          final double solid = front - _edge;
          final double from = isRtl ? rect.right - solid : rect.left + solid;
          final double to = isRtl ? rect.right - front : rect.left + front;

          canvas.saveLayer(rect, Paint());
          bright.paint(canvas, Offset.zero);
          canvas
            ..drawRect(
              rect,
              Paint()
                ..blendMode = BlendMode.dstIn
                ..shader = ui.Gradient.linear(
                  Offset(from, 0),
                  Offset(to, 0),
                  const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                ),
            )
            ..restore();
        }
        canvas.restore();
        filled -= rect.width;
      }

      if (word.end - word.start >= _longWord && progress > 0 && progress < 1) {
        _paintLetterGlow(canvas, dim, bright, start, end, rise, progress);
      }
    }

    dim.dispose();
    bright.dispose();
  }

  /// Lights up the letters of a held word one after another.
  void _paintLetterGlow(
    Canvas canvas,
    TextPainter layout,
    TextPainter bright,
    int start,
    int end,
    double rise,
    double progress,
  ) {
    final String word = text.substring(start, end).trimRight();
    int offset = start;
    int index = 0;
    final int count = word.characters.length;

    for (final String letter in word.characters) {
      final int from = offset;
      offset += letter.length;
      final double strength = letterGlowStrength(progress, index++, count);
      if (strength <= 0) {
        continue;
      }

      for (final TextBox box in layout.getBoxesForSelection(
        TextSelection(baseOffset: from, extentOffset: offset),
        boxHeightStyle: ui.BoxHeightStyle.max,
      )) {
        final Rect rect = box.toRect();
        // The glowing letter also rises a little above its word.
        final double lift = rise + 2 * strength;

        canvas.saveLayer(
          rect.inflate(14),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, 0.85 * strength)
            ..imageFilter = ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        );
        canvas
          ..save()
          ..translate(0, -lift)
          ..clipRect(rect);
        bright.paint(canvas, Offset.zero);
        canvas
          ..restore()
          ..restore()
          ..save()
          ..translate(0, -lift)
          ..clipRect(rect);
        bright.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_KaraokePainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.words != words ||
        oldDelegate.style != style ||
        oldDelegate.textAlign != textAlign ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.position != position;
  }
}
