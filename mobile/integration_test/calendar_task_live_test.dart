import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/task_display.dart';
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
  const labelId = String.fromEnvironment('CALENDAR_LABEL_ID');

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

      await until(
        () =>
            find.byType(CalendarInteractionSurface).evaluate().isNotEmpty &&
            find
                .byWidgetPredicate(
                  (w) => w is CalendarTaskHandle && w.record.id == taskId,
                )
                .hitTestable()
                .evaluate()
                .isNotEmpty,
      );
      final handle = find
          .byWidgetPredicate(
            (w) => w is CalendarTaskHandle && w.record.id == taskId,
          )
          .hitTestable()
          .first;
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
      expect(handle, findsOneWidget);
      final sourceHandle = t.widget<CalendarTaskHandle>(handle);
      expect(sourceHandle.constraints, isNotNull);
      expect(sourceHandle.record.fields['capabilities']['reschedule'], isTrue);
      expect(surface.writable, isTrue);
      expect(surface.pending, isNull);
      final gesture = await t.startGesture(t.getCenter(handle));
      await t.pump(const Duration(milliseconds: 650));
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
      for (var frame = 0; frame < 150; frame++) {
        await t.pump(const Duration(milliseconds: 20));
        if (surface.drag.target == null) {
          await gesture.moveTo(
            Offset(viewport.left + viewport.width * .6, viewport.bottom - 18),
          );
        }
        if (surface.drag.target?.day.month != start.month &&
            surface.drag.target != null) {
          break;
        }
      }
      expect(surface.drag.target, isNotNull);
      expect(surface.drag.target!.day.month, isNot(start.month));
      final expected = surface.drag.preview!;
      await capture('preview');
      await gesture.up();
      await until(() => find.text('确认移动排期').evaluate().isNotEmpty);
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
      await capture('approved');

      // Long press an actually empty day through the production create route.
      final createDay = DateTime(month.year, month.month, month.day + 12);
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
      await t.tap(find.descendant(of: label, matching: find.byType(InkWell)).first);
      await t.pumpAndSettle();
      await t.tap(find.text(taskTagLabels[labelId]!).hitTestable().last);
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
      await until(
        () => find.byType(FormPage).evaluate().isEmpty,
      );
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
        Command('approve', {'id': createReview.id, 'reason': '独立审核新建'}),
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
