import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:pandora_mobile/features/calendar/holiday_data.dart';
import 'support/local_test_state.dart';

void main() {
  for (final mode in ['online', 'cached-offline', 'first-offline']) {
    testWidgets('$mode shows festival only once and separate vacation badges', (
      t,
    ) async {
      await t.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(
            MockRepository(const Session(), store: DemoStore()),
          ),
          selectedDateProvider.overrideWith((r) => DateTime(2026, 10, 1)),
          holidayCalendarProvider.overrideWith(
            (r, y) => loadHolidayCalendar(
              y,
              readCache: (year) async =>
                  mode == 'cached-offline' && year == 2026
                  ? '{"year":2026,"status":"FRESH","days":[{"date":"2026-10-02","name":"国庆节","isOffDay":true},{"date":"2026-10-10","name":"国庆节","isOffDay":false}]}'
                  : null,
              writeCache: (_, _) async {},
              fetchYear: (year) async {
                if (mode != 'online') throw StateError('offline');
                return {
                  'year': year,
                  'status': 'FRESH',
                  'days': year == 2026
                      ? [
                          {
                            'date': '2026-10-02',
                            'name': '国庆节',
                            'isOffDay': true,
                          },
                          {
                            'date': '2026-10-10',
                            'name': '国庆节',
                            'isOffDay': false,
                          },
                        ]
                      : [],
                };
              },
            ),
          ),
        ],
      );
      await t.pumpWidget(
        OwnedTestProviderScope(
          container: c,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: const Scaffold(body: CalendarContent(availableHeight: 700)),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('国庆节'), findsOneWidget);
      expect(find.textContaining('★'), findsNothing);
      expect(find.text('假期待更新'), findsNothing);
      expect(
        find.text('休'),
        mode == 'first-offline' ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('班'),
        mode == 'first-offline' ? findsNothing : findsOneWidget,
      );
      if (mode == 'first-offline') {
        expect(find.textContaining('暂无放假调休信息'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
  for (final count in [0, 1, 4, 5, 6, 10, 12]) {
    testWidgets('month displays $count tasks and full agenda', (t) async {
      final store = DemoStore();
      store.records['reviews'] = [];
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
          holidayCalendarProvider.overrideWith((r, y) async* {
            yield const HolidayCalendar({
              '2026-10-01': HolidayDay('国庆节', true),
            }, '');
          }),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        OwnedTestProviderScope(
          container: c,
          child: const MaterialApp(
            home: Scaffold(body: CalendarContent(availableHeight: 700)),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('month-span:tasks:'),
        ),
        findsNWidgets(count > 5 ? 4 : count),
      );
      expect(find.text('国庆节'), findsOneWidget);
      expect(find.textContaining('★'), findsNothing);
      final overflow = find.byKey(const ValueKey('month-overflow:2026-10-01'));
      if (count > 5) {
        expect(find.text('+${count - 4}'), findsOneWidget);
        expect(t.getSize(overflow).height, greaterThanOrEqualTo(48));
        await t.longPress(overflow);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('calendar-day-agenda')), findsNothing);
        expect(store.records['reviews'], isEmpty);
        await t.tap(overflow);
      } else {
        expect(overflow, findsNothing);
        final cell = t.getRect(
          find.byKey(const ValueKey('month-day:2026-10-1')),
        );
        await t.tapAt(Offset(cell.center.dx, cell.bottom - 5));
      }
      await t.pumpAndSettle();
      expect(find.text('$count 条记录'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('agenda:tasks:'),
        ),
        findsNWidgets(count),
      );
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'adjacent month opens its actual date even without holiday data',
    (t) async {
      final store = DemoStore();
      store.records['tasks'] = [
        const Record(
          id: 'adjacent',
          title: '相邻月份真实任务',
          fields: {
            'startAt': '2026-09-29T09:00:00+08:00',
            'deadline': '2026-09-30T18:00:00+08:00',
          },
        ),
      ];
      final c = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(
            MockRepository(const Session(), store: store),
          ),
          selectedDateProvider.overrideWith((r) => DateTime(2026, 10, 1)),
          holidayCalendarProvider.overrideWith(
            (r, y) => Stream.value(const HolidayCalendar({}, '节假日暂不可用')),
          ),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        OwnedTestProviderScope(
          container: c,
          child: const MaterialApp(
            home: Scaffold(body: CalendarContent(availableHeight: 700)),
          ),
        ),
      );
      await t.pumpAndSettle();
      final adjacent = find.byKey(
        const ValueKey(
          'adjacent-month-span:tasks:adjacent:2026-09-28T00:00:00.000',
        ),
      );
      expect(adjacent, findsOneWidget);
      final rect = t.getRect(adjacent);
      await t.tapAt(Offset(rect.right - 8, rect.center.dy));
      await t.pumpAndSettle();
      expect(
        sameDay(c.read(selectedDateProvider), DateTime(2026, 9, 30)),
        isTrue,
      );
      expect(find.byKey(const ValueKey('calendar-day-agenda')), findsOneWidget);
      expect(find.text('1 条记录'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('cross year opens December with a long official holiday label', (
    t,
  ) async {
    final c = testContainer(
      overrides: [
        selectedDateProvider.overrideWith((r) => DateTime(2027, 1, 1)),
        holidayCalendarProvider.overrideWith((r, y) async* {
          yield const HolidayCalendar({
            '2026-12-31': HolidayDay('跨年节假日长名称用于验证完整提示与省略显示', true),
          }, '');
        }),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      OwnedTestProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: CalendarContent(availableHeight: 700)),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byTooltip('跨年节假日长名称用于验证完整提示与省略显示'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('month-day:2026-12-31')));
    await t.pumpAndSettle();
    expect(
      sameDay(c.read(selectedDateProvider), DateTime(2026, 12, 31)),
      isTrue,
    );
    expect(find.byKey(const ValueKey('calendar-day-agenda')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  test('festival name is separate from vacation and makeup workday', () {
    expect(const HolidayDay('国庆节', false).label, '国庆节');
    expect(const HolidayDay('', false).arrangementLabel, '班');
    expect(const HolidayDay('', true).arrangementLabel, '休');
    expect(const HolidayDay('春节').arrangementLabel, '');
  });
}
