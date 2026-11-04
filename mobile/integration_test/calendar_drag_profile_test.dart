import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_interaction.dart';
import 'package:pandora_mobile/features/calendar/calendar_schedule.dart';

/// Measures real long-press/edge scrolling in profile mode. Never submits a move.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'ten real cross-month drags produce bounded frame evidence',
    (tester) async {
      expect(AppConfig.mock, isFalse);
      const token = String.fromEnvironment('CALENDAR_TEST_TOKEN');
      const taskId = String.fromEnvironment('CALENDAR_TASK_ID');
      final repository = HttpRepository(AppConfig.baseUrl, token);
      final original = await repository.detail('tasks', taskId);
      final source = CalendarSchedule.fromRecord(original).firstDay;
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(
            (ref) => const Session(
              id: String.fromEnvironment('CALENDAR_ISSUER'),
              companyId: String.fromEnvironment('CALENDAR_COMPANY'),
              token: token,
            ),
          ),
          repositoryProvider.overrideWithValue(repository),
          selectedDateProvider.overrideWith(
            (ref) => DateTime(source.year, source.month, source.day),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() => repository.dio.close(force: true));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PandoraApp(),
        ),
      );
      container.read(routerProvider).go('/view');
      Future<void> until(bool Function() done) async {
        final end = DateTime.now().add(const Duration(seconds: 30));
        while (!done() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(done(), isTrue);
      }

      await until(
        () => find.byType(CalendarInteractionSurface).evaluate().isNotEmpty,
      );
      final state = tester.state<CalendarInteractionSurfaceState>(
        find.byType(CalendarInteractionSurface),
      );
      await until(
        () =>
            !state.restoring &&
            find
                .byWidgetPredicate(
                  (w) => w is CalendarTaskHandle && w.record.id == taskId,
                )
                .hitTestable()
                .evaluate()
                .isNotEmpty,
      );
      final timings = <FrameTiming>[];
      var measuring = false;
      void onTimings(List<FrameTiming> values) {
        if (measuring) timings.addAll(values);
      }

      SchedulerBinding.instance.addTimingsCallback(onTimings);
      addTearDown(
        () => SchedulerBinding.instance.removeTimingsCallback(onTimings),
      );
      final samples = <Map<String, Object>>[];
      for (var iteration = 0; iteration < 10; iteration++) {
        // Reset only the viewport; the gesture itself uses the production recognizer.
        state.drag.scroll.jumpTo(0);
        await tester.pumpAndSettle();
        final handle = find
            .byWidgetPredicate(
              (w) => w is CalendarTaskHandle && w.record.id == taskId,
            )
            .hitTestable()
            .first;
        final item = tester.widget<CalendarTaskHandle>(handle);
        final point = tester.getCenter(handle);
        final diagnostics =
            'iteration=${iteration + 1} '
            'restoring=${state.restoring} writable=${state.writable} '
            'pending=${state.pending != null} '
            'hit=${state.drag.hit(point)?.day}';
        expect(state.writable, isTrue, reason: diagnostics);
        expect(state.pending, isNull, reason: diagnostics);
        expect(item.constraints, isNotNull, reason: diagnostics);
        final gesture = await tester.startGesture(point);
        await tester.pump(const Duration(milliseconds: 650));
        expect(
          state.drag.active,
          isTrue,
          reason: '$diagnostics message=${state.message}',
        );
        final viewport = state.drag.bounds!;
        final last = DateTime.utc(source.year, source.month + 1, 0);
        final lastCell = find
            .byKey(ValueKey('month-day:${last.year}-${last.month}-${last.day}'))
            .hitTestable();
        measuring = true;
        final firstFrame = timings.length;
        await gesture.moveTo(
          Offset(tester.getCenter(lastCell).dx, viewport.bottom - 18),
        );
        for (var frame = 0; frame < 180; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          if (state.drag.target != null &&
              state.drag.target!.day.month != source.month) {
            break;
          }
          if (state.drag.target == null) {
            await gesture.moveTo(
              Offset(viewport.left + viewport.width * .6, viewport.bottom - 18),
            );
          }
        }
        expect(state.drag.target, isNotNull);
        expect(state.drag.target!.day.month, isNot(source.month));
        state.drag.cancel();
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        measuring = false;
        samples.add({
          'iteration': iteration + 1,
          'frames': timings.length - firstFrame,
        });
        expect(state.pending, isNull);
        expect(
          (await repository.detail('tasks', taskId)).version,
          original.version,
        );
      }
      expect(timings, isNotEmpty);
      final slow = timings
          .where((f) => f.totalSpan.inMicroseconds > 16667)
          .length;
      final long = timings
          .where((f) => f.totalSpan.inMicroseconds > 100000)
          .length;
      final maxSpan = timings
          .map((f) => f.totalSpan.inMicroseconds)
          .reduce((a, b) => a > b ? a : b);
      binding.reportData = {
        'mode': 'profile',
        'device': 'emulator-5556 / API37 / swiftshader',
        'dragCount': 10,
        'frameCount': timings.length,
        'slowFrameCount': slow,
        'slowFrameRatio': slow / timings.length,
        'over100msCount': long,
        'maxSpanUs': maxSpan,
        'performanceTargetMet': slow / timings.length <= .05 && long == 0,
        'samples': samples,
      };
      // Measurement remains an honest result even if the emulator misses the target.
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
