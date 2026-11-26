import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retropod/core/constants/app_palette.dart';
import 'package:retropod/core/extensions/duration_label_extensions.dart';
import 'package:retropod/core/services/audio_player_service.dart';

/// A full-width draggable progress bar with the times underneath.
class PlaybackProgressBar extends ConsumerStatefulWidget {
  /// Shows a handle while the click wheel is scrubbing.
  final bool showHandle;

  const PlaybackProgressBar({super.key, this.showHandle = false});

  @override
  ConsumerState<PlaybackProgressBar> createState() =>
      _PlaybackProgressBarState();
}

class _PlaybackProgressBarState extends ConsumerState<PlaybackProgressBar> {
  /// Position under the finger while dragging, from 0 to 1.
  double? _dragFraction;

  void _drag(double x, double width) {
    setState(() => _dragFraction = (x / width).clamp(0.0, 1.0));
  }

  Future<void> _finishDrag(Duration total) async {
    final double? fraction = _dragFraction;
    if (fraction == null) {
      return;
    }
    await ref.read(audioPlayerProvider).seek(total * fraction);
    if (mounted) {
      setState(() => _dragFraction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.read(audioPlayerProvider);
    final bool isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: StreamBuilder<Duration>(
        stream: player.positionStream,
        builder: (context, snapshot) {
          final Duration total = player.duration ?? Duration.zero;
          final Duration position = snapshot.data ?? player.position;
          final double playedFraction = total > Duration.zero
              ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
              : 0;
          final double fraction = _dragFraction ?? playedFraction;
          final Duration shown = total * fraction;
          final bool isDragging = _dragFraction != null;

          return LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;

              return Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        _drag(details.localPosition.dx, width),
                    onTapUp: (_) async => _finishDrag(total),
                    onHorizontalDragStart: (details) =>
                        _drag(details.localPosition.dx, width),
                    onHorizontalDragUpdate: (details) =>
                        _drag(details.localPosition.dx, width),
                    onHorizontalDragEnd: (_) async => _finishDrag(total),
                    onHorizontalDragCancel: () =>
                        setState(() => _dragFraction = null),
                    child: SizedBox(
                      height: 24,
                      width: width,
                      child: _buildTrack(width, fraction, isDragging, isDark),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTime(shown.toClockLabel()),
                      _buildTime('-${(total - shown).toClockLabel()}'),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTrack(
    double width,
    double fraction,
    bool isDragging,
    bool isDark,
  ) {
    // The bar grows while it is being dragged.
    final double thickness = isDragging ? 16 : 10;

    return Stack(
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: thickness,
          width: width,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0x4DFFFFFF)
                : AppPalette.inActiveSliderGradientColor2,
            borderRadius: BorderRadius.circular(thickness / 2),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: ColoredBox(
              color: isDark
                  ? CupertinoColors.white
                  : AppPalette.selectedTileGradientColor1,
            ),
          ),
        ),
        if (widget.showHandle)
          Positioned(
            left: (width - 18) * fraction,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CupertinoColors.white,
                boxShadow: [
                  BoxShadow(color: Color(0x66000000), blurRadius: 4),
                ],
              ),
              child: SizedBox.square(dimension: 18),
            ),
          ),
      ],
    );
  }

  Widget _buildTime(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.bold,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
