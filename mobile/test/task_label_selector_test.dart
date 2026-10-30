import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/shared/task_label_selector.dart';

class LabelAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  Completer<void>? hold;
  List<Map<String, Object>> labels = [
    {
      'id': 'db-custom-927',
      'name': '门店质量核验',
      'color': '#CFE5FF',
      'status': 'ACTIVE',
    },
    {
      'id': 'db-disabled',
      'name': '旧标签',
      'color': '#E7D4FF',
      'status': 'DISABLED',
    },
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final waiting = hold;
    if (waiting != null) await waiting.future;
    final body = options.path == '/task-labels'
        ? status == 200
              ? {'items': labels}
              : {'code': 'LABEL_ERROR', 'message': '读取失败'}
        : {'id': 'new-task', 'title': '门店核验', 'version': 1};
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late LabelAdapter adapter;
  late HttpRepository repository;
  late TextEditingController controller;
  late GlobalKey<FormState> form;
  late ProviderContainer container;

  setUp(() {
    adapter = LabelAdapter();
    repository = HttpRepository('http://test.invalid/api', 'test-token');
    repository.dio.httpClientAdapter = adapter;
    controller = TextEditingController();
    form = GlobalKey<FormState>();
    container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(
          (ref) => const Session(token: 'test-token'),
        ),
        repositoryProvider.overrideWithValue(repository),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    repository.dio.close(force: true);
    controller.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              child: TaskLabelSelector(
                controller: controller,
                historicalName: '旧标签',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'reads real catalog, shows server color and submits database ID',
    (t) async {
      await mount(t);
      await t.pumpAndSettle();
      expect(adapter.requests.single.path, '/task-labels');
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer test-token',
      );
      await t.tap(find.byKey(const ValueKey('task-label-select')));
      await t.pumpAndSettle();
      expect(find.text('旧标签'), findsNothing);
      expect(find.text('重要'), findsNothing);
      await t.tap(find.text('门店质量核验'));
      await t.pumpAndSettle();
      expect(controller.text, 'db-custom-927');
      expect(form.currentState!.validate(), isTrue);
      final chip = t.widget<Container>(
        find.byKey(const ValueKey('task-label-selected')),
      );
      expect((chip.decoration as BoxDecoration).color, const Color(0xFFCFE5FF));
      await repository.execute(
        'tasks',
        Command('create', {
          'title': '门店核验',
          'participantIds': ['member-1'],
          'tagId': controller.text,
          'startAt': '2026-11-02T09:00:00+08:00',
          'deadline': '2026-11-03T18:00:00+08:00',
        }, idempotencyKey: 'label-contract'),
      );
      final post = adapter.requests.last;
      expect(post.path, '/tasks');
      expect(post.data['labelId'], 'db-custom-927');
    },
  );

  testWidgets('loading catalog blocks submission', (t) async {
    adapter.hold = Completer<void>();
    await mount(t);
    expect(find.text('正在加载标签…'), findsOneWidget);
    expect(form.currentState!.validate(), isFalse);
    adapter.hold!.complete();
    await t.pumpAndSettle();
    expect(find.text('选择标签'), findsOneWidget);
  });

  testWidgets('failed catalog offers retry without fixed fallback', (t) async {
    adapter.status = 400;
    await mount(t);
    await t.pumpAndSettle();
    expect(find.text('标签加载失败，请重试'), findsOneWidget);
    expect(form.currentState!.validate(), isFalse);
    expect(find.text('重要'), findsNothing);
    adapter.status = 200;
    await t.tap(find.text('重新加载标签'));
    await t.pumpAndSettle();
    expect(find.text('选择标签'), findsOneWidget);
    expect(adapter.requests.length, 2);
  });

  testWidgets('empty catalog blocks submit and permits refresh', (t) async {
    adapter.labels.clear();
    await mount(t);
    await t.pumpAndSettle();
    expect(find.text('当前没有可用标签'), findsOneWidget);
    expect(form.currentState!.validate(), isFalse);
    expect(find.text('刷新标签'), findsOneWidget);
  });

  testWidgets(
    'async editing backfill shows valid label; disabled ID requires replacement',
    (t) async {
      await mount(t);
      await t.pumpAndSettle();
      controller.text = 'db-custom-927';
      await t.pumpAndSettle();
      expect(find.text('门店质量核验'), findsOneWidget);
      expect(form.currentState!.validate(), isTrue);
      controller.text = 'db-disabled';
      await t.pumpAndSettle();
      expect(find.textContaining('原标签：旧标签'), findsOneWidget);
      expect(form.currentState!.validate(), isFalse);
    },
  );

  testWidgets('catalog refresh invalidates an unavailable selected label', (
    t,
  ) async {
    controller.text = 'db-custom-927';
    await mount(t);
    await t.pumpAndSettle();
    expect(form.currentState!.validate(), isTrue);
    adapter.labels.clear();
    container.invalidate(recordsProvider('task-labels'));
    await t.pumpAndSettle();
    expect(form.currentState!.validate(), isFalse);
    expect(find.byKey(const ValueKey('task-label-selected')), findsNothing);
  });
}
