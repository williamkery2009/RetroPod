/// Moves further per wheel step the longer the wheel keeps spinning quickly.
class ScrollAccelerator {
  /// Lists shorter than this always move one item at a time.
  static const int minimumListLength = 30;

  /// Steps further apart than this start a new spin.
  static const Duration maximumGap = Duration(milliseconds: 180);

  DateTime? _lastStepAt;
  bool? _wasForward;
  int _streak = 0;

  /// Returns how many items to move for a wheel step made at [now].
  int stepSize({
    required DateTime now,
    required bool isForward,
    required int listLength,
  }) {
    final DateTime? lastStepAt = _lastStepAt;
    final bool continuesSpin =
        lastStepAt != null &&
        now.difference(lastStepAt) <= maximumGap &&
        _wasForward == isForward;

    _streak = continuesSpin ? _streak + 1 : 0;
    _lastStepAt = now;
    _wasForward = isForward;

    if (listLength < minimumListLength || _streak < 8) {
      return 1;
    }
    return _streak < 20 ? 2 : 5;
  }
}

/// The letter shown while fast scrolling past [title]. Digits and symbols
/// are grouped under `#`.
String indexLetter(String title) {
  final String trimmed = title.trim();
  if (trimmed.isEmpty) {
    return '#';
  }
  final String first = String.fromCharCode(trimmed.runes.first);
  final bool isSymbol = RegExp(
    r'[\p{N}\p{P}\p{S}]',
    unicode: true,
  ).hasMatch(first);
  return isSymbol ? '#' : first.toUpperCase();
}
