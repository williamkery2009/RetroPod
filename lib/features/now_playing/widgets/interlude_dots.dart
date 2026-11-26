import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// Three dots that fill over an instrumental break from [start] to [end].
class InterludeDots extends StatelessWidget {
  final Duration start;
  final Duration end;
  final ValueListenable<Duration> position;

  const InterludeDots({
    super.key,
    required this.start,
    required this.end,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: position,
      builder: (context, now, _) {
        final bool isVisible = now >= start && now < end;
        final double progress = isVisible
            ? (now - start).inMicroseconds / (end - start).inMicroseconds
            : 0;
        // One slow breath every three seconds.
        final double breath =
            1 + 0.1 * math.sin(now.inMilliseconds * 2 * math.pi / 3000);

        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: !isVisible
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.scale(
                      scale: breath,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < 3; i++)
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: CupertinoColors.white.withValues(
                                  alpha:
                                      0.25 +
                                      0.75 * (progress * 3 - i).clamp(0, 1),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
