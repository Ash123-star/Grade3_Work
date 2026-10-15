import 'support/flutter_sdk_assets.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/complete_list.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/common/demo_pages.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'support/local_test_state.dart';

class CalendarAdapter implements HttpClientAdapter {
  CalendarAdapter([this.failure = '']);
  final String failure;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final cursor = int.parse('${options.queryParameters['cursor'] ?? 0}');
    final later = cursor > 0;
    if (later && failure == 'forbidden') {
      return ResponseBody.fromString(
        '{"code":"FORBIDDEN"}',
        403,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    final tasks = options.path == '/tasks';
    final items = tasks
        ? [
            {
              'id': 'deadline',
              'title': '发布截止点',
              'owner_id': 'u1',
              'deadline': '2026-01-15T01:00:00Z',
            },
            {
              'id': 'timed',
              'title': '有真实时段的工作',
              'owner_id': 'u1',
              'deadline': '2026-01-15T04:00:00Z',
              'fields': {
                'startAt': '2026-01-15T02:00:00Z',
                'endAt': '2026-01-15T03:30:00Z',
              },
            },
          ]
        : [
            for (var i = cursor; i < (later ? 31 : 30); i++)
              {
                'id': failure == 'duplicate' && later ? '0' : '$i',
                'title': i == 30 ? '最后一页正式日报' : '日报${i + 1}',
                'business_date':
                    '2026-01-${(i + 1).toString().padLeft(2, '0')}',
                'owner_id': 'u1',
                'submitted': i != 0,
                'body': {'work': i == 0 ? '草稿内容不能计入' : '正式工作${i + 1}'},
              },
          ];
    final body = {
      'items': later && failure == 'empty' ? [] : items,
      'total': tasks
          ? 2
          : later && failure == 'changed'
          ? 32
          : 31,
      if (failure != 'missing') 'nextCursor': failure == 'repeat' ? '0' : '30',
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

HttpRepository repository(CalendarAdapter adapter) {
  final repo = HttpRepository('http://calendar.test', 'test-token');
  repo.dio.httpClientAdapter = adapter;
  return repo;
}

Widget host(ProviderContainer container, Widget child, {double scale = 1.5}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: appTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );

void main() {
  test(
    '31st record and original scoped HTTP query survive complete pagination',
    () async {
      final adapter = CalendarAdapter(), repo = repository(adapter);
      final range = BusinessRange(DateTime(2026, 1, 15), '月');
      final page = await readCompleteList(
        repo,
        'logs',
        Query(search: '工作', ownerId: 'u1', from: range.from, to: range.to),
      );
      expect(page.items.length, 31);
      expect(page.items.last.title, '最后一页正式日报');
      expect(adapter.requests.length, 2);
      for (final request in adapter.requests) {
        expect(request.queryParameters['date'], '2026-01-01');
        expect(request.queryParameters['period'], 'month');
        expect(request.queryParameters['ownerId'], 'u1');
        expect(request.queryParameters['search'], '工作');
        expect(request.queryParameters['limit'], 30);
      }
      expect(adapter.requests.last.queryParameters['cursor'], '30');
    },
  );

  for (final (failure, kind) in [
    ('repeat', FailureKind.server),
    ('missing', FailureKind.server),
    ('empty', FailureKind.server),
    ('duplicate', FailureKind.conflict),
    ('changed', FailureKind.conflict),
    ('forbidden', FailureKind.forbidden),
  ]) {
    test(
      'incomplete pagination $failure never returns a successful partial list',
      () async {
        final adapter = CalendarAdapter(failure);
        await expectLater(
          readCompleteList(repository(adapter), 'logs', const Query()),
          throwsA(isA<ApiFailure>().having((e) => e.kind, 'kind', kind)),
        );
        expect(adapter.requests.length, lessThanOrEqualTo(2));
      },
    );
  }

  test(
    'disposed read stops before request and Shanghai dates cross leap/year/midnight',
    () async {
      final adapter = CalendarAdapter();
      await expectLater(
        readCompleteList(
          repository(adapter),
          'logs',
          const Query(),
          isActive: () => false,
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(adapter.requests, isEmpty);
      expect(businessEventTime('2025-12-31T16:00:00Z'), DateTime(2026, 1, 1));
      expect(
        businessEventTime('2026-01-01T01:00:00+09:00'),
        DateTime(2026, 1, 1),
      );
      expect(businessEventTime('2026-01-01'), DateTime(2026, 1, 1));
      expect(businessEventTime('invalid'), isNull);
      final leap = BusinessRange(DateTime(2024, 2, 29), '月');
      expect(leap.to.difference(leap.from).inDays, 29);
      expect(shanghaiWallTime(leap.from), DateTime(2024, 2, 1));
      final yearWeek = BusinessRange(DateTime(2026, 1, 1), '周');
      expect(shanghaiWallTime(yearWeek.from), DateTime(2025, 12, 29));
      expect(
        isSubmittedDiary(
          const Record(
            id: 'x',
            title: 'x',
            fields: {'submitted': false, 'status': '已提交'},
          ),
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'calendar, diary filter and report have independent complete scoped reads',
    (t) async {
      final adapter = CalendarAdapter();
      final container = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repository(adapter)),
          sessionProvider.overrideWith((ref) => const Session()),
          selectedDateProvider.overrideWith((ref) => DateTime(2026, 1, 15)),
          periodProvider.overrideWith((ref) => '月'),
          reportDateProvider.overrideWith((ref) => DateTime(2026, 1, 15)),
          reportPeriodProvider.overrideWith((ref) => '月'),
          logFilterDateProvider.overrideWith((ref) => DateTime(2025, 12, 31)),
        ],
      );
      addTearDown(container.dispose);
      await t.runAsync(() async {
        final calendarSubscription = container.listen(
          datedRecordsProvider('logs'),
          (_, _) {},
        );
        expect(
          (await container.read(
            datedRecordsProvider('logs').future,
          )).items.length,
          31,
        );
        final diarySubscription = container.listen(
          logDayRecordsProvider(('logs', 'u2')),
          (_, _) {},
        );
        expect(
          (await container.read(
            logDayRecordsProvider(('logs', 'u2')).future,
          )).items.length,
          31,
        );
        final reportSubscription = container.listen(
          reportRecordsProvider,
          (_, _) {},
        );
        expect(
          (await container.read(reportRecordsProvider.future)).items.length,
          31,
        );
        calendarSubscription.close();
        diarySubscription.close();
        reportSubscription.close();
      });
      expect(adapter.requests.map((e) => e.queryParameters['date']), [
        '2026-01-01',
        '2026-01-01',
        '2025-12-31',
        '2025-12-31',
        '2026-01-01',
        '2026-01-01',
      ]);
      expect(adapter.requests[2].queryParameters['ownerId'], 'u2');
      expect(adapter.requests.last.queryParameters['ownerId'], 'u1');
      container.read(selectedDateProvider.notifier).state = DateTime(
        2027,
        7,
        7,
      );
      expect(container.read(reportDateProvider), DateTime(2026, 1, 15));
      expect(container.read(logFilterDateProvider), DateTime(2025, 12, 31));
    },
  );

  testWidgets(
    'report excludes draft body, includes last-page source and missing date',
    (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final container = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repository(CalendarAdapter())),
          reportDateProvider.overrideWith((ref) => DateTime(2026, 1, 15)),
          reportPeriodProvider.overrideWith((ref) => '月'),
        ],
      );
      addTearDown(container.dispose);
      await t.pumpWidget(
        host(container, const PeriodReport(initialPeriod: '月')),
      );
      await settleLocalIo(t);
      expect(find.text('已收集 30 份源日报'), findsOneWidget);
      expect(find.text('1 份草稿未提交，未计入回顾与源日报'), findsOneWidget);
      expect(find.text('尚无正式日报的日期：1/1'), findsOneWidget);
      expect(find.textContaining('草稿内容不能计入'), findsNothing);
      expect(find.text('最后一页正式日报'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('whole week has no internal scroll and opens complete day', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final container = testContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repository(CalendarAdapter())),
        sessionProvider.overrideWith(
          (ref) => const Session(token: 'test-token'),
        ),
        selectedDateProvider.overrideWith((ref) => DateTime(2026, 1, 15)),
        periodProvider.overrideWith((ref) => '周'),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(host(container, const CalendarContent()));
    await settleLocalIo(t);
    final overview = find.byKey(const ValueKey('calendar-week-overview'));
    expect(overview, findsOneWidget);
    expect(
      find.descendant(of: overview, matching: find.byType(Scrollable)),
      findsNothing,
    );
    for (var day = 1; day <= 7; day++) {
      expect(find.byKey(ValueKey('week-day:$day')), findsOneWidget);
    }
    final first = t.getTopLeft(find.byKey(const ValueKey('week-day:1')));
    expect(
      t.getSize(find.byKey(const ValueKey('week-pill:tasks:deadline'))).width,
      156,
    );
    for (var day = 2; day <= 7; day++) {
      final current = t.getTopLeft(find.byKey(ValueKey('week-day:$day')));
      expect(current.dx, first.dx);
      expect(current.dy, greaterThan(first.dy));
    }
    await t.tap(find.byKey(const ValueKey('week-day:4')));
    await t.pumpAndSettle();
    expect(find.text('发布截止点'), findsOneWidget);
    expect(find.text('有真实时段的工作'), findsOneWidget);
    expect(find.text('日报15'), findsOneWidget);
    expect(find.text('3 条记录'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('render actual 360dp large-text day week and report', (t) async {
    final loader = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
          ),
        ),
      );
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              materialIconsFontPath,
            ).readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final (period, route, name) in [
      ('日', '/view/day', '44-calendar-day-large'),
      ('周', '/view/week', '45-calendar-week-large'),
      ('月', '/report', '46-report-large'),
    ]) {
      final container = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repository(CalendarAdapter())),
          sessionProvider.overrideWith((ref) => const Session()),
          fontScaleProvider.overrideWith((ref) => 1.5),
          selectedDateProvider.overrideWith((ref) => DateTime(2026, 1, 15)),
          periodProvider.overrideWith((ref) => period),
          reportDateProvider.overrideWith((ref) => DateTime(2026, 1, 15)),
          reportPeriodProvider.overrideWith((ref) => '月'),
        ],
      );
      final boundaryKey = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: UncontrolledProviderScope(
            container: container,
            child: const PandoraApp(),
          ),
        ),
      );
      container.read(routerProvider).go(route);
      await settleLocalIo(t);
      if (route == '/report') {
        await t.tap(find.text('月报'));
        await settleLocalIo(t);
        expect(container.read(reportPeriodProvider), '月');
      }
      expect(t.takeException(), isNull, reason: name);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await t.runAsync(() async {
        final rendered = await boundary.toImage(pixelRatio: 1);
        final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'docs/evidence/stage3-rebuild/$name.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        rendered.dispose();
      });
      await t.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });
}
