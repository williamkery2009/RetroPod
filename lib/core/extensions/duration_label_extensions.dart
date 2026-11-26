extension DurationLabel on Duration {
  /// Formats as `m:ss`. Negative durations show as `0:00`.
  String toClockLabel() {
    final int seconds = isNegative ? 0 : inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
