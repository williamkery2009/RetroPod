import 'dart:async';

import 'package:flutter/cupertino.dart';

/// Briefly shows a large letter over the current screen while fast scrolling.
class IndexLetterPopup {
  final ValueNotifier<String> _letter = ValueNotifier('');
  OverlayEntry? _entry;
  Timer? _hideTimer;

  void show(BuildContext context, String letter) {
    _letter.value = letter;
    if (_entry == null) {
      final OverlayEntry entry = OverlayEntry(builder: _build);
      _entry = entry;
      Overlay.of(context).insert(entry);
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 700), hide);
  }

  void hide() {
    _hideTimer?.cancel();
    _entry
      ?..remove()
      ..dispose();
    _entry = null;
  }

  void dispose() {
    hide();
    _letter.dispose();
  }

  Widget _build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 90,
          height: 90,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ValueListenableBuilder<String>(
            valueListenable: _letter,
            builder: (context, letter, _) => Text(
              letter,
              style: const TextStyle(
                fontFamily: 'Liberation Sans',
                fontSize: 52,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.white,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
