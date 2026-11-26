import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retropod/features/now_playing/widgets/lyric_focus.dart';

void main() {
  testWidgets(
    'inactive lyrics blur but focus and browsing immediately clear it',
    (tester) async {
      Widget line({bool active = false, bool browsing = false}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: LyricFocus(
              isActive: active,
              isBrowsing: browsing,
              child: const Text('Readable lyrics'),
            ),
          );
      await tester.pumpWidget(line());
      await tester.pumpAndSettle();
      expect(
        tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
        isTrue,
      );
      await tester.pumpWidget(line(active: true));
      expect(
        tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
        isFalse,
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(line());
      await tester.pumpAndSettle();
      expect(
        tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
        isTrue,
      );
      await tester.pumpWidget(line(browsing: true));
      expect(
        tester.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled,
        isFalse,
      );
    },
  );
}
