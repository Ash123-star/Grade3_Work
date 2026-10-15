import 'support/local_test_state.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

class SupportingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final notes = <Map<String, dynamic>>[];
  int readStatus = 200, saveStatus = 200;
  final profile = <String, dynamic>{
    'id': 'u1',
    'name': '林小满',
    'version': 7,
    'profile': {'introduction': '服务端原介绍', 'avatarAttachmentId': 'owned-avatar'},
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reading = options.method == 'GET';
    final status = reading ? readStatus : saveStatus;
    dynamic body;
    if (status != 200) {
      body = {'code': status == 409 ? 'VERSION_CONFLICT' : 'FORBIDDEN'};
    } else if (options.path == '/private-notes') {
      if (reading) {
        body = notes;
      } else {
        final value = Map<String, dynamic>.from(options.data as Map);
        final index = notes.indexWhere(
          (n) =>
              n['resource'] == value['resource'] &&
              n['object_id'] == value['objectId'] &&
              n['owner_id'] == 'u1',
        );
        body = <String, dynamic>{
          'id': index < 0 ? 'server-note-uuid' : notes[index]['id'],
          'owner_id': 'u1',
          'resource': value['resource'],
          'object_id': value['objectId'],
          'text': value['text'],
          'version': (value['version'] as int) + 1,
        };
        if (index < 0) {
          notes.add(body as Map<String, dynamic>);
        } else {
          notes[index] = body as Map<String, dynamic>;
        }
      }
    } else if (options.path.startsWith('/profiles/')) {
      if (!reading) {
        profile['profile'] = Map<String, dynamic>.from(options.data as Map)
          ..remove('version');
        profile['version'] = (profile['version'] as int) + 1;
      }
      body = profile;
    } else {
      body = {'items': []};
    }
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
  late HttpRepository repo;
  late SupportingAdapter adapter;
  setUp(() {
    repo = HttpRepository('http://localhost/api', 'fixture-token');
    adapter = SupportingAdapter();
    repo.dio.httpClientAdapter = adapter;
  });
  Map<String, dynamic> note(
    String resource,
    String object,
    String owner,
    String text, {
    int version = 4,
  }) => {
    'id': 'uuid-$object-$owner',
    'resource': resource,
    'object_id': object,
    'owner_id': owner,
    'text': text,
    'version': version,
  };
  final notFound = isA<ApiFailure>().having(
    (e) => e.kind,
    'kind',
    FailureKind.notFound,
  );
  final validation = isA<ApiFailure>().having(
    (e) => e.kind,
    'kind',
    FailureKind.validation,
  );

  test('note lookup separates UUID, object, resource and owner', () async {
    adapter.notes.addAll([
      note('tasks', 'item', 'u1', '任务备注'),
      note('dashboard/company', 'item', 'u2', '他人私密内容'),
      note('dashboard/company', 'other', 'u1', '另一对象'),
      note('dashboard/company', 'item', 'u1', '我的公司重点备注'),
    ]);
    final result = await repo.detail(
      'private-notes',
      'dashboard/company:item:u1',
    );
    expect(result.id, 'uuid-item-u1');
    expect(result.fields['备注'], '我的公司重点备注');
    expect(result.version, 4);
    expect(adapter.requests.single.queryParameters, isEmpty);
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer fixture-token',
    );
    await expectLater(
      repo.detail('private-notes', 'tasks:absent:u1'),
      throwsA(notFound),
    );
  });

  test(
    'note create and update send underlying object and correct versions',
    () async {
      final created = await repo.execute(
        'private-notes',
        const Command('save', {'id': 'dashboard/company:item:u1', '备注': '新建'}),
      );
      expect(adapter.requests.last.data, {
        'resource': 'dashboard/company',
        'objectId': 'item',
        'text': '新建',
        'version': 0,
      });
      expect(created.id, 'server-note-uuid');
      expect(created.fields['备注'], '新建');
      final existing = await repo.detail(
        'private-notes',
        'dashboard/company:item:u1',
      );
      await repo.execute(
        'private-notes',
        Command('save', {
          'id': 'dashboard/company:item:u1',
          '备注': '更新',
        }, version: existing.version),
      );
      expect((adapter.requests.last.data as Map)['version'], 1);
      expect(adapter.notes.single['version'], 2);
    },
  );

  test('invalid and unsupported note keys issue no HTTP request', () async {
    for (final key in [
      'uuid-only',
      'tasks::u1',
      'tasks:item:',
      'dashboard/personal:item:u1',
    ]) {
      await expectLater(repo.detail('private-notes', key), throwsA(validation));
      await expectLater(
        repo.execute(
          'private-notes',
          Command('save', {'id': key, '备注': '不能保存'}),
        ),
        throwsA(validation),
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test(
    'profile nested content maps and existing avatar reference survives save',
    () async {
      final profile = await repo.detail('organization/profile', 'u1');
      expect(profile.title, '林小满');
      expect(profile.fields['个人介绍'], '服务端原介绍');
      expect(profile.fields['avatarAttachmentId'], 'owned-avatar');
      final updated = await repo.execute(
        'organization/profile',
        Command('update', {
          '个人介绍': '更新介绍',
          '姓名': '不得提交的新姓名',
          '头像': 'local.png',
          'avatarAttachmentId': profile.fields['avatarAttachmentId'],
        }, version: profile.version),
      );
      expect(adapter.requests.last.data, {
        'introduction': '更新介绍',
        'avatarAttachmentId': 'owned-avatar',
        'version': 7,
      });
      expect(updated.fields['个人介绍'], '更新介绍');
      expect(updated.title, '林小满');
    },
  );

  Future<ProviderContainer> launch(WidgetTester t, String route) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => const Session()),
        repositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const PandoraApp()),
    );
    c.read(routerProvider).go(route);
    // Dio's asynchronous adapter runs outside the fake timer zone.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
    return c;
  }

  Future<void> settleHttp(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
  }

  Future<void> disposeUi(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  }

  testWidgets(
    'own note editor reads HTTP text and preserves input on conflict',
    (t) async {
      adapter.notes.add(
        note('dashboard/company', 'item', 'u1', '服务端备忘', version: 6),
      );
      await launch(t, '/form/note?id=dashboard%2Fcompany%3Aitem%3Au1');
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '服务端备忘',
      );
      await t.enterText(find.byType(TextFormField).first, '尚未提交的修改');
      adapter.saveStatus = 409;
      await t.tap(find.widgetWithText(FilledButton, '私人备注'));
      await settleHttp(t);
      expect((adapter.requests.last.data as Map)['version'], 6);
      expect(find.text('内容已有新版本，请刷新后再提交'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '尚未提交的修改',
      );
      expect(adapter.notes.single['text'], '服务端备忘');
      await disposeUi(t);
    },
  );

  testWidgets('absent supported note creates and reopens using HTTP result', (
    t,
  ) async {
    final c = await launch(t, '/form/note?id=tasks%3Aitem%3Au1');
    await t.enterText(find.byType(TextFormField).first, '新备注正文');
    await t.tap(find.widgetWithText(FilledButton, '私人备注'));
    await settleHttp(t);
    expect(adapter.notes.single['object_id'], 'item');
    expect(adapter.notes.single['text'], '新备注正文');
    c.read(routerProvider).go('/me/profile');
    await settleHttp(t);
    c.read(routerProvider).go('/form/note?id=tasks%3Aitem%3Au1');
    await settleHttp(t);
    expect(
      t
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      '新备注正文',
    );
    await disposeUi(t);
  });

  testWidgets('forbidden note load disables save and reveals no body', (
    t,
  ) async {
    adapter.readStatus = 403;
    await launch(t, '/form/note?id=tasks%3Aitem%3Au1');
    final save = find.widgetWithText(FilledButton, '重试提交');
    expect(t.widget<FilledButton>(save).onPressed, isNull);
    expect(find.text('你没有访问这项内容的权限'), findsOneWidget);
    expect(adapter.requests.where((r) => r.method == 'PUT'), isEmpty);
    await disposeUi(t);
  });

  testWidgets(
    'foreign account note key is rejected before fetching private data',
    (t) async {
      await launch(t, '/form/note?id=tasks%3Aitem%3Au2');
      expect(find.text('仅本人可以读取私人备注'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '重试提交'))
            .onPressed,
        isNull,
      );
      expect(
        adapter.requests.where((r) => r.path == '/private-notes'),
        isEmpty,
      );
      await disposeUi(t);
    },
  );

  testWidgets(
    'profile UI preserves avatar/version and keeps identity read-only',
    (t) async {
      final c = await launch(t, '/form/profile-edit');
      final inputs = find.byType(TextFormField);
      final name = t.widget<TextFormField>(inputs.at(0));
      expect(
        t.widget<EditableText>(find.byType(EditableText).first).readOnly,
        isTrue,
      );
      expect(name.controller!.text, '林小满');
      expect(t.widget<TextFormField>(inputs.at(1)).controller!.text, '服务端原介绍');
      await t.enterText(inputs.at(1), '经过服务端保存的新介绍');
      await t.tap(find.widgetWithText(FilledButton, '编辑个人资料'));
      await settleHttp(t);
      final put = adapter.requests.lastWhere((r) => r.method == 'PUT');
      expect(put.data, {
        'introduction': '经过服务端保存的新介绍',
        'avatarAttachmentId': 'owned-avatar',
        'version': 7,
      });
      expect(c.read(sessionProvider).name, '林小满');
      if (!AppConfig.mock) {
        expect(find.text('选择并上传新头像'), findsOneWidget);
        expect(find.text('选择头像（仅本地）'), findsNothing);
      }
      await disposeUi(t);
    },
  );

  testWidgets('real unsupported note target cannot be submitted', (t) async {
    await launch(t, '/form/note?id=dashboard%2Fpersonal%3Aitem%3Au1');
    expect(find.text('私人备注仅支持公司重点和任务，请从对应详情进入'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '重试提交'))
          .onPressed,
      isNull,
    );
    expect(adapter.requests.where((r) => r.path == '/private-notes'), isEmpty);
    await disposeUi(t);
  });
}
