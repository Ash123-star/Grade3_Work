import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/shared/sibling_swipe.dart';

void main() {
  testWidgets(
    'sibling follows drag, commits once, and rejects boundary outward',
    (tester) async {
      var index = 0, commits = 0, outer = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: GuardedHorizontalDrag(
                canDrag: (_) => true,
                onStart: (_) {},
                onUpdate: (_) {},
                onEnd: (_) => outer++,
                onCancel: () {},
                child: SiblingSwipe(
                  index: index,
                  itemCount: 2,
                  onStep: (step) {
                    setState(() {
                      index += step;
                      commits++;
                    });
                    return true;
                  },
                  child: SizedBox.expand(
                    child: Center(child: Text('page $index')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final drag = await tester.startGesture(const Offset(600, 250));
      await drag.moveBy(const Offset(-220, 0));
      await tester.pump();
      await drag.moveBy(const Offset(-100, 0));
      await tester.pump();
      expect(tester.getCenter(find.text('page 0')).dx, lessThan(400));
      expect(index, 0);
      await drag.up();
      await tester.pumpAndSettle();
      expect(index, 1);
      expect(commits, 1);
      expect(outer, 0);
      expect(tester.getCenter(find.text('page 1')).dx, closeTo(400, 1));
      await tester.dragFrom(const Offset(600, 250), const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(index, 1);
      expect(outer, 1);
    },
  );

  testWidgets(
    'short drags spring back; vertical, edge and keyboard do not switch',
    (tester) async {
      var commits = 0;
      Widget screen({double keyboard = 0}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: SiblingSwipe(
            index: 0,
            itemCount: 2,
            onStep: (_) {
              commits++;
              return true;
            },
            child: const SizedBox.expand(child: Center(child: Text('current'))),
          ),
        ),
      );
      await tester.pumpWidget(screen());
      final short = await tester.startGesture(const Offset(400, 250));
      await short.moveBy(const Offset(-35, 0));
      await tester.pump(const Duration(milliseconds: 500));
      await short.up();
      await tester.pumpAndSettle();
      expect(commits, 0);
      expect(tester.getCenter(find.text('current')).dx, closeTo(400, 1));
      await tester.dragFrom(const Offset(300, 250), const Offset(0, 180));
      await tester.dragFrom(const Offset(8, 250), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(commits, 0);
      await tester.pumpWidget(screen(keyboard: 250));
      await tester.dragFrom(const Offset(300, 250), const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(commits, 0);
    },
  );

  testWidgets('multi-touch cancels sibling navigation', (tester) async {
    var commits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SiblingSwipe(
            index: 0,
            itemCount: 2,
            onStep: (_) {
              commits++;
              return true;
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final first = await tester.startGesture(const Offset(500, 250), pointer: 1);
    await first.moveBy(const Offset(-40, 0));
    final second = await tester.startGesture(
      const Offset(600, 250),
      pointer: 2,
    );
    await first.moveBy(const Offset(-180, 0));
    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    expect(commits, 0);
  });

  testWidgets('horizontal content scrolling retains its own drag', (
    tester,
  ) async {
    var commits = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SiblingSwipe(
            index: 0,
            itemCount: 2,
            onStep: (_) {
              commits++;
              return true;
            },
            child: SingleChildScrollView(
              controller: scroll,
              scrollDirection: Axis.horizontal,
              child: const SizedBox(width: 1600, height: 200),
            ),
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(500, 100), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(commits, 0);
  });
}
