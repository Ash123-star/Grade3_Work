import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/personal_todos/application/todo_providers.dart';
import 'package:pandora_mobile/features/personal_todos/data/personal_todo.dart';
import 'package:pandora_mobile/features/personal_todos/data/todo_repository.dart';
import 'package:pandora_mobile/features/personal_todos/presentation/daily_todos_section.dart';
import 'package:pandora_mobile/shared/calendar/civil_date.dart';

void main() {
  testWidgets(
    'Flutter UI -> real HTTP -> PostgreSQL private todo lifecycle',
    (t) async {
      HttpOverrides.global = null;
      final config =
          jsonDecode(
                File(
                  '${Platform.environment['HOME_LIVE_DIR']}/fixture.json',
                ).readAsStringSync().replaceFirst('\uFEFF', ''),
              )
              as Map;
      final clients = <HttpRepository>[];
      Future<HttpRepository> login(String who) async {
        final public = HttpRepository(config['baseUrl'] as String, null);
        clients.add(public);
        final result = await public.dio.post<Map<String, dynamic>>(
          '/auth/login',
          data: {'account': 'home-$who', 'password': config['password']},
        );
        final client = HttpRepository(
          config['baseUrl'] as String,
          result.data!['token'] as String,
        );
        clients.add(client);
        return client;
      }

      addTearDown(() {
        for (final c in clients) {
          c.dio.close(force: true);
        }
      });
      late HttpRepository alice, bob, outsider;
      await t.runAsync(() async {
        alice = await login('alice');
        bob = await login('bob');
        outsider = await login('outsider');
      });
      final repo = HttpTodoRepository(alice.dio);
      final date = civilDate(shanghaiToday());
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(
            (ref) => const Session(id: 'home-alice'),
          ),
          todoRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      t.view.physicalSize = const Size(390, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 100; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await t.pump(const Duration(milliseconds: 50));
          if (condition()) return;
        }
        fail('Live UI did not reach expected state');
      }

      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: DailyTodosSection()),
            ),
          ),
        ),
      );
      await waitFor(() => find.text('添加一件小事').evaluate().isNotEmpty);
      await t.tap(find.text('事项'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('todo-title')),
        'Live private item',
      );
      await t.tap(find.text('保存'));
      await waitFor(
        () =>
            find.byType(AlertDialog).evaluate().isEmpty &&
            find.text('Live private item').evaluate().isNotEmpty,
      );
      await t.ensureVisible(find.byType(Checkbox).first);
      await t.tap(find.byType(Checkbox).first);
      await waitFor(
        () =>
            find.byType(AlertDialog).evaluate().isEmpty &&
            find.text('已完成').evaluate().isNotEmpty,
      );
      late PersonalTodo item;
      await t.runAsync(() async {
        // Keep this real-clock API client separate from sockets created by widget frames.
        final freshAlice = await login('alice');
        final relogged = HttpTodoRepository(freshAlice.dio);
        item = (await relogged.day(date, '0')).items.single;
        expect(item.completed, true);
        for (final client in [bob, outsider]) {
          final other = HttpTodoRepository(client.dio);
          await expectLater(
            other.detail(item.id),
            throwsA(
              isA<ApiFailure>().having(
                (e) => e.kind,
                'kind',
                FailureKind.notFound,
              ),
            ),
          );
          await expectLater(
            other.execute(
              TodoCommand('PUT', item.id, {
                ...item.editBody,
                'title': 'stolen',
              }),
            ),
            throwsA(isA<ApiFailure>()),
          );
        }
        await relogged.execute(
          TodoCommand('PUT', item.id, {
            ...item.editBody,
            'completed': false,
            'date': '2028-02-29',
          }),
        );
        item = await relogged.detail(item.id);
        expect(item.date, '2028-02-29');
        expect(item.completed, false);
        await relogged.execute(
          TodoCommand('PUT', item.id, {...item.editBody, 'date': date}),
        );
        for (final client in [freshAlice, bob]) {
          final first = await client.list(
            'tasks/received-card',
            const Query(limit: 10),
          );
          final second = await client.list(
            'tasks/received-card',
            const Query(limit: 10, cursor: '10'),
          );
          expect(first.total, 12);
          expect(first.items.length + second.items.length, 12);
        }
        expect(
          (await outsider.list('tasks/received-card', const Query())).items,
          isEmpty,
        );
      });
      container.invalidate(todoDayProvider);
      container.invalidate(todoMonthProvider);
      await waitFor(() => find.text('未完成').evaluate().isNotEmpty);
      await t.ensureVisible(find.byTooltip('编辑或删除：Live private item'));
      await t.tap(find.byTooltip('编辑或删除：Live private item'));
      await t.pumpAndSettle();
      await t.tap(find.text('删除'));
      await t.pumpAndSettle();
      await t.tap(find.text('删除').last);
      await waitFor(
        () =>
            find.byType(AlertDialog).evaluate().isEmpty &&
            find.text('Live private item').evaluate().isEmpty,
      );
      await t.runAsync(() async {
        final refreshed = HttpTodoRepository((await login('alice')).dio);
        expect((await refreshed.day(date, '0')).total, 0);
      });
      await t.pumpWidget(const SizedBox.shrink());
      for (final client in clients) {
        client.dio.close(force: true);
      }
      await t.pump(const Duration(seconds: 5));
    },
    skip: Platform.environment['HOME_LIVE_DIR'] == null,
  );
}
