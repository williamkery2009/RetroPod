import 'dart:async';

import 'package:flutter/cupertino.dart';

/// Makes [child] spring into place after the list jumps by [distance].
///
/// A change of [bounceId] starts a new spring. A larger [delayStep] starts
/// it later, so lines move one after another.
class SpringOffset extends StatefulWidget {
  final int bounceId;
  final double distance;
  final int delayStep;
  final Widget child;

  const SpringOffset({
    super.key,
    required this.bounceId,
    required this.distance,
    required this.delayStep,
    required this.child,
  });

  @override
  State<SpringOffset> createState() => _SpringOffsetState();
}

class _SpringOffsetState extends State<SpringOffset>
    with SingleTickerProviderStateMixin {
  static const int _delayMilliseconds = 45;
  static const int _moveMilliseconds = 600;

  /// Overshoots slightly before settling.
  static const Curve _spring = Cubic(0.3, 1.25, 0.4, 1);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );
  Curve _curve = _spring;
  double _from = 0;

  double get _offset => _from * (1 - _curve.transform(_controller.value));

  @override
  void didUpdateWidget(SpringOffset oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bounceId == widget.bounceId) {
      return;
    }

    // Keeps the line where it is on screen, even in mid-spring.
    _from = _offset + widget.distance;
    final int delay = widget.delayStep * _delayMilliseconds;
    final int total = delay + _moveMilliseconds;
    _curve = Interval(delay / total, 1, curve: _spring);
    _controller.duration = Duration(milliseconds: total);
    unawaited(_controller.forward(from: 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, _offset), child: child),
    );
  }
}
