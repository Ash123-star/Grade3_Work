import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/shared/sibling_pager.dart';

void main() {
  testWidgets(
    'adjacent pages meet during dragging and route changes once at rest',
    (tester) async {
      var index = 0, commits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: SiblingPager(
                index: index,
                itemCount: 3,
                onSelected: (next) => setState(() {
                  index = next;
                  commits++;
                }),
                itemBuilder: (context, page) => ColoredBox(
                  key: ValueKey('page-$page'),
                  color: Colors.white,
                  child: Center(child: Text('category $page')),
                ),
              ),
            ),
          ),
        ),
      );
      final drag = await tester.startGesture(const Offset(650, 250));
      await drag.moveBy(const Offset(-80, 0));
      await tester.pump();
      await drag.moveBy(const Offset(-260, 0));
      await tester.pump();
      final current = tester.getRect(find.byKey(const ValueKey('page-0')));
      final next = tester.getRect(find.byKey(const ValueKey('page-1')));
      expect(current.left, lessThan(0));
      expect(current.right, closeTo(next.left, .01));
      expect(next.right, greaterThanOrEqualTo(800));
      expect(commits, 0);
      await drag.up();
      await tester.pumpAndSettle();
      expect(index, 1);
      expect(commits, 1);
      expect(
        tester.getRect(find.byKey(const ValueKey('page-1'))).left,
        closeTo(0, .01),
      );
    },
  );

  testWidgets('multi-touch cancels navigation and restores the selected page', (
    tester,
  ) async {
    var commits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SiblingPager(
            index: 0,
            itemCount: 2,
            onSelected: (_) => commits++,
            itemBuilder: (context, page) => SizedBox.expand(
              key: ValueKey('page-$page'),
              child: Text('category $page'),
            ),
          ),
        ),
      ),
    );
    final first = await tester.startGesture(const Offset(650, 250), pointer: 1);
    await first.moveBy(const Offset(-280, 0));
    await tester.pump();
    final second = await tester.startGesture(
      const Offset(500, 350),
      pointer: 2,
    );
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(commits, 0);
    expect(
      tester.getRect(find.byKey(const ValueKey('page-0'))).left,
      closeTo(0, .01),
    );
  });
}
