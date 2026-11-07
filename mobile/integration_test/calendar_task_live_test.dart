import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_interaction.dart';
import 'package:pandora_mobile/features/calendar/calendar_schedule.dart';
import 'package:pandora_mobile/features/common/form_page.dart';

/// Disposable fixture credentials are supplied by scripts/test-calendar-live.ps1.
/// No mock repositories, in-memory databases or fake secure storage are used.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const token = String.fromEnvironment('CALENDAR_TEST_TOKEN');
  const reviewerToken = String.fromEnvironment('CALENDAR_REVIEWER_TOKEN');
  const company = String.fromEnvironment('CALENDAR_COMPANY');
  const issuer = String.fromEnvironment('CALENDAR_ISSUER');
  const taskId = String.fromEnvironment('CALENDAR_TASK_ID');

  testWidgets(
    'Android drag across month, independent approval and read back',
    (t) async {
      expect(AppConfig.mock, isFalse);
      expect(token.isNotEmpty && reviewerToken.isNotEmpty, isTrue);
      final repository = HttpRepository(AppConfig.baseUrl, token);
      final reviewer = HttpRepository(AppConfig.baseUrl, reviewerToken);
      final source = await repository.detail('tasks', taskId);
      final original = CalendarSchedule.fromRecord(source);
      final start = original.firstDay;
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(
            (ref) => Session(
              id: issuer,
              companyId: company,
              token: token,
              role: UserRole.leader,
              name: '月历设备测试',
            ),
          ),
          repositoryProvider.overrideWithValue(repository),
          selectedDateProvider.overrideWith(
            (ref) => DateTime(start.year, start.month, start.day),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() {
        repository.dio.close(force: true);
        reviewer.dio.close(force: true);
      });
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PandoraApp(),
        ),
      );
      container.read(routerProvider).go('/view');
      Future<void> until(bool Function() done) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!done() && DateTime.now().isBefore(deadline)) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(done(), isTrue);
      }

      final handles = find.byWidgetPredicate(
        (w) =>
            w is CalendarTaskHandle &&
            w.record.id == taskId &&
            w.constraints != null &&
            w.record.fields['capabilities']['reschedule'] == true,
      );
      await until(
        () =>
            find.byType(CalendarInteractionSurface).evaluate().isNotEmpty &&
            handles.hitTestable().evaluate().isNotEmpty,
      );
      final surface = t.state<CalendarInteractionSurfaceState>(
        find.byType(CalendarInteractionSurface),
      );
      await until(() => !surface.restoring);
      await binding.convertFlutterSurfaceToImage();
      Future<void> capture(String name) async {
        await t.pump();
        await binding.takeScreenshot('calendar-$name');
      }

      await capture('before');
      final sourceHandle = t.widget<CalendarTaskHandle>(
        handles.hitTestable().first,
      );
      expect(sourceHandle.constraints, isNotNull);
      expect(sourceHandle.record.fields['capabilities']['reschedule'], isTrue);
      expect(surface.writable, isTrue);
      expect(surface.pending, isNull);

      Future<TestGesture> pickUp() async {
        final nativeView = View.of(surface.context);
        bool imeHidden() =>
            surface.mounted &&
            nativeView.viewInsets.bottom == 0 &&
            MediaQuery.viewInsetsOf(surface.context).bottom == 0;
        // Dialog dismissal, IME resize and timeline layout complete separately
        // on a live device. Reacquire both the bar and its real date geometry.
        await until(
          () =>
              !surface.restoring &&
              !surface.busy &&
              !surface.confirming &&
              surface.pointers == 0 &&
              surface.pending == null &&
              ModalRoute.of(surface.context)?.isCurrent == true &&
              find.text('确认移动排期').evaluate().isEmpty,
        );
        // pumpAndSettle alone can finish before Android delivers the final IME
        // metrics. Wait for those metrics, reveal the source, then require its
        // painted position and the viewport/scroll offset to agree across frames.
        await until(imeHidden);
        expect(handles, findsWidgets);
        final reveal = handles.at(handles.evaluate().length > 1 ? 1 : 0);
        final scrollBeforeReveal = surface.widget.scroll.offset;
        await Scrollable.ensureVisible(t.element(reveal), alignment: .5);
        final layoutDeadline = DateTime.now().add(const Duration(seconds: 5));
        ({Rect bar, Rect? viewport, double scroll})? previous;
        var stableFrames = 0;
        while (DateTime.now().isBefore(layoutDeadline) && stableFrames < 3) {
          await t.pump(const Duration(milliseconds: 100));
          if (!imeHidden() ||
              surface.widget.scroll.position.isScrollingNotifier.value ||
              reveal.evaluate().isEmpty) {
            previous = null;
            stableFrames = 0;
            continue;
          }
          final sample = (
            bar: t.getRect(reveal),
            viewport: surface.drag.bounds,
            scroll: surface.widget.scroll.offset,
          );
          stableFrames = sample == previous ? stableFrames + 1 : 0;
          previous = sample;
        }
        if (stableFrames < 3) {
          await capture('pickup-layout-failed');
          fail('IME/source/viewport layout did not stabilize before pickup');
        }
        final viewport = surface.drag.bounds!;
        final candidates =
            <({Offset point, DateTime day, CalendarTaskHandle handle})>[];
        for (final node in handles.evaluate()) {
          final finder = find.byWidget(node.widget);
          final bar = t.getRect(finder);
          ({Offset point, DateTime day, CalendarTaskHandle handle})? best;
          for (final geometry in surface.drag.targets.values) {
            final cell = geometry.rect;
            if (cell == null ||
                dateLabel(
                  geometry.day,
                ).isBefore(dateLabel(original.firstDay)) ||
                dateLabel(
                  geometry.day,
                ).isAfter(dateLabel(scheduleWallTime(original.end)))) {
              continue;
            }
            final intersection = bar
                .intersect(cell)
                .intersect(viewport.deflate(8));
            if (intersection.width < 4 || intersection.height < 4) continue;
            final point = intersection.center;
            final alignment = Alignment(
              2 * (point.dx - bar.left) / bar.width - 1,
              2 * (point.dy - bar.top) / bar.height - 1,
            );
            if (surface.drag.hit(point) != geometry ||
                finder.hitTestable(at: alignment).evaluate().isEmpty) {
              continue;
            }
            if (best == null ||
                (point - bar.center).distanceSquared <
                    (best.point - bar.center).distanceSquared) {
              best = (
                point: point,
                day: geometry.day,
                handle: node.widget as CalendarTaskHandle,
              );
            }
          }
          if (best != null) candidates.add(best);
        }
        expect(
          candidates,
          isNotEmpty,
          reason: 'pickup needs a writable bar over a loaded real date',
        );
        // A long fixture still exercises a continuation when one is visible.
        final pickup = candidates[candidates.length > 1 ? 1 : 0];
        expect(pickup.handle.record.version, source.version);
        expect(surface.drag.hit(pickup.point)!.day, pickup.day);
        final gesture = await t.startGesture(pickup.point);
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (surface.drag.intent == null &&
            DateTime.now().isBefore(deadline)) {
          await t.pump(const Duration(milliseconds: 100));
        }
        if (surface.drag.intent == null) {
          await capture('pickup-failed');
          final diagnostics =
              'point=${pickup.point}, day=${businessDateText(pickup.day)}, '
              'scrollBeforeReveal=$scrollBeforeReveal, '
              'scrollAtPickup=${previous!.scroll}, '
              'scrollNow=${surface.widget.scroll.offset}, '
              'hitNow=${surface.drag.hit(pickup.point)?.day}, '
              'insetsNow=${nativeView.viewInsets.bottom}, '
              'pointers=${surface.pointers}, restoring=${surface.restoring}, '
              'busy=${surface.busy}, confirming=${surface.confirming}, '
              'writable=${surface.writable}, message=${surface.message}';
          await gesture.cancel();
          fail(
            'real long press did not start drag within 5 seconds: $diagnostics',
          );
        }
        expect(surface.drag.intent!.record.id, taskId);
        expect(surface.drag.intent!.record.version, source.version);
        expect(dateLabel(surface.drag.intent!.anchor), dateLabel(pickup.day));
        return gesture;
      }

      for (var attempt = 0; attempt < 8; attempt++) {
        final repeated = await pickUp();
        final destination = surface.drag.intent!.anchor.add(
          const Duration(days: 1),
        );
        final cell = find
            .byKey(
              ValueKey(
                'month-day:${destination.year}-${destination.month}-${destination.day}',
              ),
            )
            .hitTestable();
        await repeated.moveTo(t.getCenter(cell));
        await t.pump(const Duration(milliseconds: 40));
        final candidate = surface.drag.preview!;
        await repeated.up();
        await until(() => find.text('确认移动排期').evaluate().isNotEmpty);
        expect(find.text('新排期：${candidate.description}'), findsOneWidget);
        await t.tap(find.text('取消'));
        await until(
          () => !surface.confirming && find.text('确认移动排期').evaluate().isEmpty,
        );
        expect(surface.pending, isNull);
        expect(
          find.byKey(const ValueKey('calendar-read-cooldown')),
          findsNothing,
        );
      }
      final gesture = await pickUp();
      expect(surface.drag.active, isTrue);
      final viewport = surface.drag.bounds!;
      // The last day is in the bottom row. Enter its valid edge before scrolling.
      final lastDay = DateTime.utc(start.year, start.month + 1, 0);
      final lastCell = find
          .byKey(
            ValueKey(
              'month-day:${lastDay.year}-${lastDay.month}-${lastDay.day}',
            ),
          )
          .hitTestable();
      await gesture.moveTo(
        Offset(t.getCenter(lastCell).dx, viewport.bottom - 18),
      );
      Offset? safeLanding;
      for (var frame = 0; frame < 150; frame++) {
        await t.pump(const Duration(milliseconds: 20));
        if (surface.drag.target == null) {
          await gesture.moveTo(
            Offset(viewport.left + viewport.width * .6, viewport.bottom - 18),
          );
        }
        for (final day in surface.drag.targets.values) {
          final rect = day.rect;
          if (day.day.month != start.month &&
              rect != null &&
              rect.bottom < viewport.bottom - 16 &&
              viewport.deflate(50).contains(rect.center)) {
            safeLanding = rect.center;
            break;
          }
        }
        if (safeLanding != null) break;
      }
      expect(safeLanding, isNotNull);
      // Stop edge scrolling before comparing the displayed candidate and dialog.
      await gesture.moveTo(safeLanding!);
      await t.pump(const Duration(milliseconds: 40));
      expect(surface.drag.target!.day.month, isNot(start.month));
      await capture('preview');
      final previewRect = t.getRect(
        find.byKey(const ValueKey('calendar-drag-bar')),
      );
      final neighbours = find
          .byWidgetPredicate(
            (w) => w is CalendarTaskHandle && w.record.id != taskId,
          )
          .hitTestable();
      for (final element in neighbours.evaluate()) {
        expect(
          previewRect.overlaps(t.getRect(find.byWidget(element.widget))),
          isFalse,
        );
      }
      final expected = surface.drag.preview!;
      final landingDay = surface.drag.target!.day;
      await gesture.up();
      await until(() => find.text('确认移动排期').evaluate().isNotEmpty);
      expect(find.text('新排期：${expected.description}'), findsOneWidget);
      await capture('confirmation');
      // Invalid input must leave both business data and secure command queue alone.
      await t.tap(find.text('提交审核'));
      await t.pump();
      expect(find.text('请填写 1–1000 字原因'), findsOneWidget);
      expect(surface.pending, isNull);
      await t.enterText(find.byType(TextFormField), 'Android 跨月移动验收');
      await t.tap(find.text('提交审核'));
      await until(() => !surface.busy && surface.pending?.reviewId != null);
      final pending = surface.pending!;
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'taskId': taskId,
        'moveReviewId': pending.reviewId,
        'originalVersion': source.version,
        'beforeStart': original.start?.toIso8601String(),
        'beforeDeadline': original.end.toIso8601String(),
        'canceledDragCount': 8,
        'durationHours': original.end.difference(original.start!).inHours,
      });
      final protected = await container
          .read(calendarCommandStoreProvider)
          .read(container.read(sessionProvider));
      expect(protected!.key, pending.key);
      final waiting = await repository.detail('tasks', taskId);
      expect(waiting.version, source.version);
      expect(CalendarSchedule.fromRecord(waiting).end, original.end);
      await capture('pending');
      final approved = await reviewer.execute(
        'reviews',
        Command('approve', {
          'id': pending.reviewId!,
          'reason': '独立审核',
        }, version: source.version),
      );
      expect(approved.fields['status'], 'APPROVED');
      await surface.confirmPending();
      await t.pump(const Duration(milliseconds: 300));
      final current = await repository.detail('tasks', taskId);
      expect(current.version, source.version + 1);
      expect(
        CalendarSchedule.fromRecord(current).end.isAtSameMomentAs(expected.end),
        isTrue,
      );
      expect(
        CalendarSchedule.fromRecord(
          current,
        ).start!.isAtSameMomentAs(expected.start!),
        isTrue,
      );
      final otherClient = await reviewer.detail('tasks', taskId);
      expect(otherClient.version, current.version);
      expect(
        CalendarSchedule.fromRecord(
          otherClient,
        ).end.isAtSameMomentAs(expected.end),
        isTrue,
      );
      // The newly selected month provider must independently fetch the new version.
      final month = expected.firstDay;
      final page = await container.read(
        calendarMonthTasksProvider((
          null,
          month.year * 12 + month.month - 1,
        )).future,
      );
      expect(
        page.items.singleWhere((r) => r.id == taskId).version,
        current.version,
      );
      expect(surface.pending, isNull);
      final crowded = page.items.where(
        (r) => r.id.startsWith('$company-busy-'),
      );
      if (crowded.isNotEmpty) {
        expect(crowded.length, 5);
        final records = [...crowded, current];
        final expectedIds = {for (final record in records) record.id};
        expect(expectedIds.length, 6);
        final day = dateLabel(landingDay);
        for (final record in records) {
          final projected = page.items.singleWhere((r) => r.id == record.id);
          final schedule = CalendarSchedule.fromRecord(projected);
          final actual = CalendarSchedule.fromRecord(record);
          expect(projected.version, record.version);
          expect(schedule.start, actual.start);
          expect(schedule.end, actual.end);
          expect(dateLabel(schedule.firstDay).isAfter(day), isFalse);
          expect(
            dateLabel(scheduleWallTime(schedule.end)).isBefore(day),
            isFalse,
          );
        }
        // The fixture's overlapping spans use start date, longest span and ID
        // order. Only its first four rows belong in the landing day's preview.
        records.sort((a, b) {
          final first = CalendarSchedule.fromRecord(a);
          final second = CalendarSchedule.fromRecord(b);
          final start = dateLabel(
            first.firstDay,
          ).compareTo(dateLabel(second.firstDay));
          if (start != 0) return start;
          final end = dateLabel(
            scheduleWallTime(second.end),
          ).compareTo(dateLabel(scheduleWallTime(first.end)));
          return end != 0 ? end : a.id.compareTo(b.id);
        });
        final visibleIds = records.take(4).map((record) => record.id).toSet();
        container.read(selectedDateProvider.notifier).state = landingDay;
        final landingCell = find.byKey(
          ValueKey(
            'month-day:${landingDay.year}-${landingDay.month}-${landingDay.day}',
          ),
        );
        final overflow = find.byKey(
          ValueKey('month-overflow:${businessDateText(landingDay)}'),
        );
        await until(
          () =>
              landingCell.evaluate().isNotEmpty &&
              overflow.evaluate().isNotEmpty,
        );
        await t.pump(const Duration(milliseconds: 300));
        await t.ensureVisible(landingCell);
        await t.pumpAndSettle();
        final cellBounds = t.getRect(landingCell);
        final rowRects = <Rect>[];
        final paintedIds = <String>[];
        final segments = find.byWidgetPredicate(
          (w) => w is CalendarTaskHandle && expectedIds.contains(w.record.id),
        );
        for (final node in segments.evaluate()) {
          final row = t.getRect(find.byWidget(node.widget));
          if (row.top < cellBounds.top ||
              row.top >= cellBounds.bottom ||
              row.left > cellBounds.center.dx ||
              row.right < cellBounds.center.dx) {
            continue;
          }
          final record = (node.widget as CalendarTaskHandle).record;
          final expectedRecord = records.singleWhere((r) => r.id == record.id);
          expect(record.version, expectedRecord.version);
          final schedule = CalendarSchedule.fromRecord(record);
          final actual = CalendarSchedule.fromRecord(expectedRecord);
          expect(schedule.start, actual.start);
          expect(schedule.end, actual.end);
          expect(row.bottom, lessThanOrEqualTo(cellBounds.bottom));
          for (final previous in rowRects) {
            expect(row.overlaps(previous), isFalse);
          }
          rowRects.add(row);
          paintedIds.add(record.id);
        }
        expect(rowRects.length, 4);
        expect(paintedIds.toSet(), visibleIds);
        expect(paintedIds.toSet().length, paintedIds.length);
        expect(
          find.descendant(of: overflow, matching: find.text('+2')),
          findsOneWidget,
        );
        final overflowBounds = t.getRect(overflow);
        for (final row in rowRects) {
          expect(row.overlaps(overflowBounds), isFalse);
        }
        await capture('approved-folded');
        await t.ensureVisible(overflow);
        await t.tap(overflow);
        final agenda = find.byKey(const ValueKey('calendar-day-agenda'));
        await until(() => agenda.evaluate().isNotEmpty);
        await t.pumpAndSettle();
        expect(dateLabel(container.read(selectedDateProvider)), day);
        expect(
          find.descendant(of: agenda, matching: find.text('6 条记录')),
          findsOneWidget,
        );
        final agendaRows = find.descendant(
          of: agenda,
          matching: find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('agenda:tasks:'),
          ),
        );
        final agendaIds = [
          for (final row in agendaRows.evaluate())
            (row.widget.key as ValueKey<String>).value.substring(
              'agenda:tasks:'.length,
            ),
        ];
        expect(agendaIds.length, 6);
        expect(agendaIds.toSet(), expectedIds);
        expect(agendaIds.toSet().length, agendaIds.length);
        for (final record in records) {
          final row = find.byKey(ValueKey('agenda:tasks:${record.id}'));
          expect(row, findsOneWidget);
          expect(
            find.descendant(of: row, matching: find.text(record.title)),
            findsOneWidget,
          );
        }
        await capture('approved-day-agenda');
        await t.tap(find.byTooltip('关闭').hitTestable());
        await until(() => agenda.evaluate().isEmpty);
      }
      await capture('approved');

      // Long press an actually empty day through the production create route.
      final createDay = scheduleWallTime(
        expected.end,
      ).add(const Duration(days: 12));
      container.read(selectedDateProvider.notifier).state = createDay;
      final cell = find.byKey(
        ValueKey(
          'month-day:${createDay.year}-${createDay.month}-${createDay.day}',
        ),
      );
      await until(() => cell.evaluate().isNotEmpty && !surface.restoring);
      await t.pump(const Duration(milliseconds: 500));
      final rect = t.getRect(cell);
      await t.longPressAt(Offset(rect.center.dx, rect.bottom - 8));
      await until(
        () => find
            .byKey(const ValueKey('calendar-create-date'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.textContaining(businessDateText(createDay)), findsWidgets);
      await capture('create-prefill');
      final title = find.descendant(
        of: find.byKey(const ValueKey('dispatch-field:任务名称')),
        matching: find.byType(TextFormField),
      );
      await t.enterText(title, 'Android blank-day create');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump(const Duration(milliseconds: 400));
      final deadlineField = find.byKey(const ValueKey('dispatch-field:截止时间'));
      await t.ensureVisible(deadlineField);
      await t.tap(
        find
            .descendant(of: deadlineField, matching: find.byType(InkWell))
            .first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('确定').hitTestable());
      await until(() => find.text('选择时间').hitTestable().evaluate().isNotEmpty);
      await t.pumpAndSettle();
      await t.tap(find.text('确定').hitTestable());
      await t.pumpAndSettle();
      await until(() => find.text('确定').hitTestable().evaluate().isEmpty);
      await capture('create-time-confirmed');
      expect(
        t.widget<TextFormField>(title).controller!.text,
        'Android blank-day create',
      );
      final label = find.byKey(const ValueKey('dispatch-field:标签'));
      await t.ensureVisible(label);
      await t.tap(
        find.descendant(of: label, matching: find.byType(InkWell)).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Calendar device label').hitTestable().last);
      await t.pumpAndSettle();
      final people = find.byKey(const ValueKey('dispatch-field:参与人'));
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump(const Duration(milliseconds: 400));
      final addPerson = find.descendant(
        of: people,
        matching: find.byType(ActionChip),
      );
      await t.ensureVisible(addPerson);
      await t.pumpAndSettle();
      await capture('create-people-action');
      await t.tap(addPerson);
      await t.pumpAndSettle();
      await capture('create-people-picker');
      await until(() => find.text('DeviceParticipant').evaluate().isNotEmpty);
      await t.tap(find.text('DeviceParticipant').last);
      await t.pump(const Duration(milliseconds: 500));
      final send = find.text('派发任务');
      await t.ensureVisible(send);
      await t.tap(send);
      await t.pumpAndSettle();
      await capture('create-submitted');
      await until(() => find.byType(FormPage).evaluate().isEmpty);
      final reviews = await repository.list('reviews', const Query());
      final createReview = reviews.items.singleWhere(
        (r) => r.fields['kind'] == 'TASK_CREATE',
      );
      expect(createReview.fields['status'], 'PENDING');
      final taskQuery = Query(
        search: 'Android blank-day create',
        from: DateTime.utc(
          createDay.year,
          createDay.month,
          1,
        ).subtract(const Duration(hours: 8)),
        to: DateTime.utc(
          createDay.year,
          createDay.month + 1,
          1,
        ).subtract(const Duration(hours: 8)),
      );
      expect((await repository.list('tasks', taskQuery)).items, isEmpty);
      await reviewer.execute(
        'reviews',
        Command('approve', {
          'id': createReview.id,
          'reason': '独立审核新建',
          'expectedVersion': createReview.fields['expected_version'],
        }),
      );
      final created = (await repository.list('tasks', taskQuery)).items.single;
      expect(created.fields['startAt'], isNull);
      expect(
        businessDateText(CalendarSchedule.fromRecord(created).firstDay),
        businessDateText(createDay),
      );
      binding.reportData!.addAll({
        'approvedVersion': current.version,
        'afterStart': expected.start?.toIso8601String(),
        'afterDeadline': expected.end.toIso8601String(),
        'createReviewId': createReview.id,
        'createdTaskId': created.id,
      });
      await capture('created');
      expect(t.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
