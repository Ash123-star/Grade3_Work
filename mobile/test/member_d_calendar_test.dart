import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:pandora_mobile/features/calendar/holiday_data.dart';
import 'support/local_test_state.dart';

void main() {
  for (final count in [0, 5, 6, 12]) {
    testWidgets('month displays $count tasks and full agenda', (t) async {
      final store = DemoStore();
      store.records['tasks'] = [
        for (var i = 0; i < count; i++)
          Record(
            id: 'd$i',
            title: '任务$i',
            fields: {'deadline': '2026-10-01T12:00:00+08:00'},
          ),
      ];
      final c = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(
            MockRepository(const Session(), store: store),
          ),
          selectedDateProvider.overrideWith((r) => DateTime(2026, 10, 1)),
          holidayCalendarProvider.overrideWith(
            (r, y) async => const HolidayCalendar({
              '2026-10-01': HolidayDay('国庆节', true),
            }, ''),
          ),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            home: Scaffold(body: CalendarContent(availableHeight: 700)),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('month-overflow:2026-10-01')),
        count > 5 ? findsOneWidget : findsNothing,
      );
      if (count > 5) expect(find.text('+${count - 4}'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith(
                'month-preview:2026-10-01:',
              ),
        ),
        findsNWidgets(count > 5 ? 4 : count),
      );
      expect(find.text('★ 国庆节'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('month-day:2026-10-1')));
      await t.pumpAndSettle();
      expect(find.text('$count 条记录'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'adjacent month opens its actual date even without holiday data',
    (t) async {
      final c = testContainer(
        overrides: [
          selectedDateProvider.overrideWith((r) => DateTime(2026, 10, 1)),
          holidayCalendarProvider.overrideWith(
            (r, y) async => const HolidayCalendar({}, '节假日暂不可用'),
          ),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            home: Scaffold(body: CalendarContent(availableHeight: 700)),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('month-day:2026-9-30')));
      await t.pumpAndSettle();
      expect(c.read(selectedDateProvider), DateTime(2026, 9, 30));
      expect(find.byKey(const ValueKey('month-day-agenda')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('cross year opens December with a long official holiday label', (
    t,
  ) async {
    final c = testContainer(
      overrides: [
        selectedDateProvider.overrideWith((r) => DateTime(2027, 1, 1)),
        holidayCalendarProvider.overrideWith(
          (r, y) async => const HolidayCalendar({
            '2026-12-31': HolidayDay('跨年节假日长名称用于验证完整提示与省略显示', true),
          }, ''),
        ),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: CalendarContent(availableHeight: 700)),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byTooltip('★ 跨年节假日长名称用于验证完整提示与省略显示'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('month-day:2026-12-31')));
    await t.pumpAndSettle();
    expect(c.read(selectedDateProvider), DateTime(2026, 12, 31));
    expect(find.byKey(const ValueKey('month-day-agenda')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  test('holiday labels distinguish makeup workday', () {
    expect(const HolidayDay('国庆节', false).label, '★ 国庆节·调休上班');
  });
}
