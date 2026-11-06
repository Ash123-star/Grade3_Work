import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/shared/notification_preview.dart';

class PreviewRepository extends MockRepository {
  PreviewRepository() : super(const Session());
  int reads = 0;
  bool forbidden = false;
  Completer<Record>? pending;
  @override
  Future<Record> detail(String resource, String id, {String? ownerId}) async {
    reads++;
    if (forbidden) throw const ApiFailure(FailureKind.forbidden, '无权查看');
    if (pending != null) return pending!.future;
    return const Record(id: 'task', title: '整理客户交付材料');
  }
}

Record message(
  String id, {
  String subtitle = '',
  Map<String, dynamic> fields = const {},
}) => Record(
  id: id,
  title: '收到新任务',
  subtitle: subtitle,
  fields: {
    'notificationType': 'TASK_ASSIGNED',
    'targetResource': 'tasks',
    'targetId': 'task',
    ...fields,
  },
);

void main() {
  late PreviewRepository repository;
  late ProviderContainer container;
  setUp(() {
    repository = PreviewRepository();
    container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        sessionProvider.overrideWith((ref) => const Session(token: 'test-token')),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> mount(WidgetTester t, List<Record> messages) => t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final value in messages) NotificationPreview(value),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'notification subtitle resolves authorized task name and shares reads',
    (t) async {
      await mount(t, [message('one'), message('two')]);
      await t.pumpAndSettle();
      expect(find.text('整理客户交付材料'), findsNWidgets(2));
      expect(repository.reads, 1);
      container.invalidate(itemProvider(('tasks', 'task')));
      await t.pumpAndSettle();
      expect(repository.reads, 2);
    },
  );

  testWidgets('existing content is preferred without additional requests', (
    t,
  ) async {
    await mount(t, [
      message('one', subtitle: '请核对预算表'),
      message('two', fields: {'taskTitle': '版本发布'}),
    ]);
    await t.pumpAndSettle();
    expect(find.text('请核对预算表'), findsOneWidget);
    expect(find.text('版本发布'), findsOneWidget);
    expect(repository.reads, 0);
  });

  testWidgets(
    'forbidden target does not leak a name or hide the notification',
    (t) async {
      repository.forbidden = true;
      await mount(t, [message('one')]);
      await t.pumpAndSettle();
      expect(find.text('关联内容已不可用或无权查看'), findsOneWidget);
      expect(find.text('整理客户交付材料'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('identity change discards late detail response', (t) async {
    final pending = Completer<Record>();
    repository.pending = pending;
    await mount(t, [message('one')]);
    await t.pump();
    container.read(sessionProvider.notifier).state = const Session(
      id: 'other',
      status: 'PENDING',
    );
    await t.pump();
    pending.complete(const Record(id: 'task', title: '旧账号敏感任务'));
    await t.pumpAndSettle();
    expect(find.text('旧账号敏感任务'), findsNothing);
    expect(find.text('关联内容已不可用或无权查看'), findsOneWidget);
  });
}
