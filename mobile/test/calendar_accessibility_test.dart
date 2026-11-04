import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:pandora_mobile/features/calendar/calendar_interaction.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'calendar_drag_widget_test.dart' show dragStore, readyInteraction;
import 'support/local_test_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [360.0, 390.0, 412.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'accessible move at $width dp and $scale x with reduced motion',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          try {
            final store = dragStore();
            final container = testContainer(
              overrides: [
                repositoryProvider.overrideWithValue(
                  MockRepository(
                    const Session(),
                    store: store,
                    clock: () => DateTime(2026, 11, 2),
                  ),
                ),
                selectedDateProvider.overrideWith(
                  (ref) => DateTime(2026, 11, 2),
                ),
              ],
            );
            addTearDown(container.dispose);
            await tester.pumpWidget(
              OwnedTestProviderScope(
                container: container,
                child: MaterialApp(
                  theme: appTheme(),
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 900),
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: true,
                      accessibleNavigation: true,
                    ),
                    child: const Scaffold(
                      body: CalendarContent(availableHeight: 650),
                    ),
                  ),
                ),
              ),
            );
            await settleLocalIo(tester);
            await tester.pumpAndSettle();
            final state = await readyInteraction(tester);
            final handle = find
                .byWidgetPredicate(
                  (w) => w is CalendarTaskHandle && w.record.id == 'move-task',
                )
                .hitTestable(at: const Alignment(0, .9))
                .first;
            final node = tester.getSemantics(handle);
            final actions = node.getSemanticsData().customSemanticsActionIds!;
            final move = actions.singleWhere(
              (id) => CustomSemanticsAction.getAction(id)?.label == '移动到日期',
            );
            node.owner!.performAction(
              node.id,
              SemanticsAction.customAction,
              move,
            );
            await tester.pumpAndSettle();
            expect(state.message, isNull);
            expect(find.text('移动到日期（上海）'), findsOneWidget);
            await tester.tap(
              find.text('取消').hitTestable(at: const Alignment(0, .9)).last,
            );
            await tester.pumpAndSettle();
            expect(state.pending, isNull);
            final day = find
                .byKey(const ValueKey('month-day:2026-11-2'))
                .hitTestable(at: const Alignment(0, .9));
            final rect = tester.getRect(day);
            await tester.tapAt(Offset(rect.center.dx, rect.bottom - 5));
            await tester.pumpAndSettle();
            final button = find.byTooltip('移动到日期');
            await tester.ensureVisible(button);
            expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
            expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(find.text('移动到日期（上海）'), findsOneWidget);
            await tester.tap(
              find.text('取消').hitTestable(at: const Alignment(0, .9)).last,
            );
            await tester.pumpAndSettle();
            expect(store.records['reviews'], isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
