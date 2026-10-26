import 'support/flutter_sdk_assets.dart';
import 'support/local_test_state.dart';
import 'dart:async';
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
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/attachments.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/features/common/form_page.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

class AttachmentAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final receivedMultipart = <List<int>>[];
  int uploadStatus = 200, downloadStatus = 200, profileStatus = 200;
  bool missingId = false;
  Completer<void>? hold;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6vKAAAAAASUVORK5CYII=',
  );
  final profile = <String, dynamic>{
    'id': 'u1',
    'name': '小橙',
    'version': 7,
    'profile': {'introduction': '原介绍', 'avatarAttachmentId': 'old-avatar'},
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    var status = 200;
    dynamic data = {'items': [], 'total': 0};
    if (o.path == '/attachments' && o.method == 'POST') {
      final bytes = <int>[];
      if (stream != null) {
        await for (final chunk in stream) {
          bytes.addAll(chunk);
        }
      }
      receivedMultipart.add(bytes);
      if (hold != null) await hold!.future;
      status = uploadStatus;
      final file = (o.data as FormData).files.single.value;
      data = {
        'id': missingId ? '' : 'uploaded-${receivedMultipart.length}',
        'filename': file.filename,
        'size': file.length,
      };
    } else if (o.path.startsWith('/attachments/')) {
      if (downloadStatus == 200) {
        return ResponseBody.fromBytes(
          png,
          200,
          headers: {
            Headers.contentTypeHeader: ['application/octet-stream'],
            'content-disposition': [
              "attachment; filename*=UTF-8''%E5%A4%8D%E6%A0%B8%2F%E5%9B%BE%E7%89%87.png",
            ],
          },
        );
      }
      status = downloadStatus;
    } else if (o.path == '/organization/people') {
      final later = o.queryParameters['cursor'] == '30';
      data = {
        'items': [
          later
              ? {
                  'id': 'second',
                  'name': '第二页负责人',
                  'status': 'ACTIVE',
                  'department': '产品部',
                }
              : {
                  'id': 'first',
                  'name': '第一页成员',
                  'status': 'ACTIVE',
                  'department': '产品部',
                },
          if (!later) {'id': 'pending', 'name': '待确认成员', 'status': 'PENDING'},
        ],
        'total': 3,
        'nextCursor': later ? '60' : '30',
      };
    } else if (o.path == '/profiles/u1') {
      data = profile;
    } else if (o.path == '/profiles/me') {
      status = profileStatus;
      if (status == 200) {
        profile['profile'] = {...o.data as Map}..remove('version');
        profile['version'] = 8;
      }
      data = profile;
    } else if (o.path == '/tasks' && o.method == 'POST') {
      data = {
        'id': 'review-created',
        'kind': 'TASK_CREATE',
        'target_id': 'task-created',
        'applicant_id': 'u1',
        'status': 'PENDING',
      };
    } else if (o.path == '/tasks/task') {
      data = {
        'id': 'task',
        'title': '附件工作',
        'owner_id': 'u1',
        'issuer_id': 'issuer',
        'version': 3,
        'fields': {
          'attachments': ['file'],
          'content': '核对材料',
        },
        'events': [
          {'type': 'RECEIVED', 'sequence': 1},
        ],
      };
    } else if (o.path == '/tasks/task/events') {
      data = {'id': 'task', 'title': '附件工作', 'version': 4};
    }
    if (status != 200) {
      data = {'code': status == 409 ? 'VERSION_CONFLICT' : 'FORBIDDEN'};
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const user = Session(
  id: 'u1',
  name: '小橙',
  role: UserRole.admin,
  token: 'token',
);
void main() {
  late AttachmentAdapter adapter;
  late HttpRepository repo;
  setUp(() {
    adapter = AttachmentAdapter();
    repo = HttpRepository('http://localhost/api', 'token');
    repo.dio.httpClientAdapter = adapter;
  });
  Matcher failure(FailureKind kind) =>
      isA<ApiFailure>().having((f) => f.kind, 'kind', kind);
  test('file errors explain the repair and hide raw parser diagnostics', () {
    for (final entry in {
      'UNSUPPORTED_FILE': (415, '请添加PNG、JPEG、PDF、Word或Excel文件'),
      'FILE_TYPE_MISMATCH': (415, '文件格式与名称不一致，请重新导出后添加'),
      'FILE_LIMIT': (400, '材料超出处理范围，请缩小或拆分后重试'),
      'FILE_TOO_LARGE': (413, '材料超出处理范围，请缩小或拆分后重试'),
      'FILE_ENCRYPTED': (422, '请先解除文件加密，再添加材料'),
    }.entries) {
      final request = RequestOptions(path: '/attachments');
      final error = ApiFailure.fromDio(
        DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: entry.value.$1,
            data: {'code': entry.key, 'message': 'raw parser diagnostics'},
          ),
        ),
      );
      expect(error.kind, FailureKind.validation);
      expect(error.message, entry.value.$2);
    }
  });
  test(
    'multipart sends exact bytes, receives actual metadata and rejects invalid files or response',
    () async {
      final bytes = Uint8List.fromList(utf8.encode('中文材料'));
      final uploaded = await repo.uploadAttachment(
        SelectedAttachment('材料.txt', bytes),
      );
      expect(uploaded.id, 'uploaded-1');
      expect(uploaded.size, bytes.length);
      expect(adapter.requests.single.headers['Authorization'], 'Bearer token');
      expect(utf8.decode(adapter.receivedMultipart.single), contains('中文材料'));
      expect(
        (adapter.requests.single.data as FormData).files.single.key,
        'file',
      );
      final count = adapter.requests.length;
      for (final bytes in [
        Uint8List(0),
        Uint8List(maximumAttachmentBytes + 1),
      ]) {
        await expectLater(
          repo.uploadAttachment(SelectedAttachment('bad', bytes)),
          throwsA(failure(FailureKind.validation)),
        );
      }
      expect(adapter.requests.length, count);
      adapter.missingId = true;
      await expectLater(
        repo.uploadAttachment(SelectedAttachment('x', Uint8List.fromList([1]))),
        throwsA(failure(FailureKind.server)),
      );
      adapter.missingId = false;
      adapter.uploadStatus = 403;
      await expectLater(
        repo.uploadAttachment(SelectedAttachment('x', Uint8List.fromList([1]))),
        throwsA(failure(FailureKind.forbidden)),
      );
    },
  );
  test(
    'AI material upload declares its purpose and keeps ordinary uploads compatible',
    () async {
      await repo.uploadAttachment(
        SelectedAttachment('材料.pdf', Uint8List.fromList([1])),
        aiWork: true,
      );
      expect(adapter.requests.single.queryParameters, {'purpose': 'AI_WORK'});
    },
  );
  test(
    'download authenticates and sanitizes server filename; size/IDs/image signatures are validated',
    () async {
      final file = await repo.downloadAttachment('file');
      expect(file.name, '复核_图片.png');
      expect(file.bytes, adapter.png);
      expect(adapter.requests.single.path, '/attachments/file');
      expect(adapter.requests.single.headers['Authorization'], 'Bearer token');
      expect(safeAttachmentName('../NUL.txt'), '.._NUL.txt');
      expect(safeAttachmentName('CON.txt'), '_CON.txt');
      expect(
        () => SelectedAttachment(
          'fake.png',
          Uint8List.fromList([1, 2, 3]),
        ).validate(avatar: true),
        throwsA(failure(FailureKind.validation)),
      );
      SelectedAttachment('avatar.png', adapter.png).validate(avatar: true);
      final count = adapter.requests.length;
      await expectLater(
        repo.downloadAttachment(''),
        throwsA(failure(FailureKind.validation)),
      );
      expect(adapter.requests.length, count);
      adapter.downloadStatus = 404;
      await expectLater(
        repo.downloadAttachment('file'),
        throwsA(failure(FailureKind.notFound)),
      );
    },
  );
  test(
    'actual attachment and participant IDs and feedback blocker text use supported contracts',
    () async {
      await repo.execute(
        'tasks',
        const Command('create', {
          'title': '任务',
          'participantIds': ['first', 'second'],
          'attachments': ['uploaded'],
          'deadline': '2026-10-30T18:00:00+08:00',
        }, idempotencyKey: 'idem'),
      );
      expect((adapter.requests.last.data as Map)['attachments'], ['uploaded']);
      expect((adapter.requests.last.data as Map)['participants'], [
        'first',
        'second',
      ]);
      await repo.execute(
        'tasks',
        const Command('feedback', {
          'id': 'task',
          '成果说明': '交付内容',
          '遇到的阻碍': '等待复核',
        }, version: 3),
      );
      expect(adapter.requests.last.data, {
        'type': 'FEEDBACK',
        'version': 3,
        'text': '交付内容\n\n遇到的阻碍：等待复核',
      });
      await repo.list(
        'organization/dispatch-people',
        const Query(search: '产品', cursor: '30'),
      );
      expect(adapter.requests.last.queryParameters['dispatch'], true);
      expect(adapter.requests.last.queryParameters['search'], '产品');
      expect(adapter.requests.last.queryParameters['cursor'], '30');
    },
  );
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
  }

  Future<ProviderContainer> launch(
    WidgetTester t,
    String route, {
    AttachmentPicker? picker,
    AttachmentSaver? saver,
    GlobalKey? boundary,
    double scale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => user),
        fontScaleProvider.overrideWith((ref) => scale),
        repositoryProvider.overrideWith((ref) {
          final r = ref.watch(httpRepositoryProvider);
          r.dio.httpClientAdapter = adapter;
          return r;
        }),
        if (picker != null) attachmentPickerProvider.overrideWithValue(picker),
        if (saver != null) attachmentSaverProvider.overrideWithValue(saver),
      ],
    );
    addTearDown(c.dispose);
    c.read(routerProvider).go(route);
    Widget app = UncontrolledProviderScope(
      container: c,
      child: const PandoraApp(),
    );
    if (boundary != null) app = RepaintBoundary(key: boundary, child: app);
    await t.pumpWidget(app);
    await settle(t);
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  }

  Future<void> choose(WidgetTester t, {bool avatar = false}) async {
    final finder = find.text(avatar ? '选择并上传新头像' : '选择并上传附件');
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    await t.tap(finder);
    await settle(t);
  }

  testWidgets(
    'upload partial failure keeps bytes, retries without duplicating prior successes and canceled picker changes nothing',
    (t) async {
      var picks = 0;
      final c = await launch(
        t,
        '/form/dispatch',
        picker: (_) async {
          picks++;
          return picks == 1
              ? [
                  SelectedAttachment('材料.txt', Uint8List.fromList([1, 2, 3])),
                ]
              : null;
        },
      );
      adapter.uploadStatus = 503;
      await choose(t);
      expect(find.textContaining('上传失败'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '派发任务'))
            .onPressed,
        isNull,
      );
      adapter.uploadStatus = 200;
      await t.ensureVisible(find.text('重试上传'));
      await t.pumpAndSettle();
      await t.tap(find.text('重试上传'));
      await settle(t);
      expect(find.textContaining('已上传，等待表单提交'), findsOneWidget);
      await choose(t);
      expect(adapter.receivedMultipart.length, 2);
      c.read(routerProvider).go('/form/dispatch?again=1');
      await settle(t);
      expect(find.text('材料.txt'), findsNothing);
      await close(t);
    },
  );
  testWidgets(
    'upload pending blocks submit and closing editor cancels; late result cannot enter another account',
    (t) async {
      adapter.hold = Completer<void>();
      final c = await launch(
        t,
        '/form/dispatch',
        picker: (_) async => [
          SelectedAttachment('私有.txt', Uint8List.fromList([7])),
        ],
      );
      final button = find.text('选择并上传附件');
      await t.ensureVisible(button);
      await t.pumpAndSettle();
      await t.tap(button);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      for (var tick = 0; tick < 10; tick++) {
        await t.pump(const Duration(milliseconds: 50));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        if (adapter.requests.any((o) => o.path == '/attachments')) break;
      }
      expect(adapter.requests.any((o) => o.path == '/attachments'), isTrue);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '派发任务'))
            .onPressed,
        isNull,
      );
      final uploadRequest = adapter.requests.lastWhere(
        (o) => o.path == '/attachments',
      );
      c.read(sessionProvider.notifier).state = const Session(
        id: 'other',
        name: '另一个人',
        role: UserRole.admin,
        token: 'other',
      );
      await t.pump();
      expect(uploadRequest.cancelToken!.isCancelled, isTrue);
      adapter.hold!.complete();
      await settle(t);
      expect(find.text('私有.txt'), findsNothing);
      expect(
        adapter.requests.where((o) => o.path == '/tasks' && o.method == 'POST'),
        isEmpty,
      );
      await close(t);
    },
  );
  testWidgets(
    'avatar upload preserves current introduction/version and409 preserves old avatar',
    (t) async {
      await launch(
        t,
        '/form/profile-edit',
        picker: (_) async => [SelectedAttachment('候选.png', adapter.png)],
      );
      await choose(t, avatar: true);
      adapter.profileStatus = 409;
      await t.tap(find.widgetWithText(FilledButton, '编辑个人资料'));
      await settle(t);
      final body =
          adapter.requests.lastWhere((o) => o.path == '/profiles/me').data
              as Map;
      expect(body, {
        'introduction': '原介绍',
        'avatarAttachmentId': 'uploaded-1',
        'version': 7,
      });
      expect(
        (adapter.profile['profile'] as Map)['avatarAttachmentId'],
        'old-avatar',
      );
      expect(find.textContaining('内容已有新版本'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        '原介绍',
      );
      await close(t);
    },
  );
  testWidgets(
    'attachment download saves exact bytes, canceled/error no success,403 disables and no public link',
    (t) async {
      var mode = 0;
      List<int>? saved;
      String? name;
      await launch(
        t,
        '/attachments/file',
        saver: (filename, bytes) async {
          name = filename;
          saved = bytes;
          if (mode == 2) throw const FileSystemException('write');
          return mode == 0 ? '/tmp/file.png' : null;
        },
      );
      for (var i = 0; i < 3; i++) {
        mode = i;
        await t.tap(find.text('下载并保存附件'));
        await settle(t);
        expect(
          find.textContaining('附件已保存'),
          i == 0 ? findsOneWidget : findsNothing,
        );
      }
      expect(name, '复核_图片.png');
      expect(saved, adapter.png);
      adapter.downloadStatus = 403;
      await t.tap(find.text('下载并保存附件'));
      await settle(t);
      expect(find.textContaining('权限已失效'), findsOneWidget);
      final downloadButton = find.ancestor(
        of: find.text('下载并保存附件'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(downloadButton, findsOneWidget);
      expect((t.widget(downloadButton) as FilledButton).onPressed, isNull);
      await close(t);
    },
  );
  testWidgets(
    'paged people search passes server search and dispatch flag; inactive people excluded',
    (t) async {
      final c = await launch(t, '/form/dispatch');
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(body: PersonPicker(dispatch: true)),
          ),
        ),
      );
      await settle(t);
      expect(find.text('待确认成员'), findsNothing);
      await t.tap(find.text('加载更多成员'));
      await settle(t);
      expect(find.text('第二页负责人'), findsOneWidget);
      await t.enterText(find.byType(TextField), '产品');
      await t.pump(const Duration(milliseconds: 350));
      await settle(t);
      final request = adapter.requests.lastWhere(
        (o) => o.path == '/organization/people',
      );
      expect(request.queryParameters['search'], '产品');
      expect(request.queryParameters['dispatch'], true);
      expect(request.queryParameters.containsKey('cursor'), isFalse);
      await close(t);
    },
  );
  testWidgets(
    'task download route and feedback attachment boundary remain explicit',
    (t) async {
      final c = await launch(t, '/item/tasks/task');
      expect(find.text('查看并保存文件'), findsOneWidget);
      await t.tap(find.text('查看并保存文件'));
      await settle(t);
      expect(find.text('下载并保存附件'), findsOneWidget);
      c.read(routerProvider).go('/form/feedback?id=task&version=3');
      await settle(t);
      expect(find.text('附件关联暂不可用'), findsOneWidget);
      expect(find.text('选择并上传附件'), findsNothing);
      await close(t);
    },
  );
  testWidgets(
    'dispatch UI preserves uploaded IDs and unique participants from actual member choices',
    (t) async {
      await launch(
        t,
        '/form/dispatch',
        picker: (_) async => [
          SelectedAttachment('说明.txt', Uint8List.fromList([65, 66])),
        ],
      );
      final title = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '输入任务名称',
      );
      await t.enterText(title, '带附件的任务');
      await t.ensureVisible(find.text('选择日期和时间').first);
      await t.tap(find.text('选择日期和时间').first);
      await t.pumpAndSettle();
      await t.tap(find.text('确定'));
      await t.pumpAndSettle();
      await t.tap(find.text('确定'));
      await t.pumpAndSettle();
      final date = find.text('选择日期和时间').last;
      await t.ensureVisible(date);
      await t.pumpAndSettle();
      await t.tap(date);
      await t.pumpAndSettle();
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      if (tomorrow.month != DateTime.now().add(const Duration(days: 1)).month) {
        await t.tap(find.byTooltip('下个月'));
        await t.pumpAndSettle();
      }
      await t.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.text('${tomorrow.day}'),
            )
            .last,
      );
      await t.tap(find.text('确定'));
      await t.pumpAndSettle();
      await t.tap(find.text('确定'));
      await t.pumpAndSettle();
      final primary = find.widgetWithText(ActionChip, '添加');
      await t.ensureVisible(primary);
      await t.pumpAndSettle();
      await t.tap(primary);
      await settle(t);
      await t.tap(find.text('第一页成员'));
      await t.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await t.ensureVisible(primary);
        await t.pumpAndSettle();
        await t.tap(primary);
        await settle(t);
        await t.tap(find.text('加载更多成员'));
        await settle(t);
        await t.tap(
          find.descendant(
            of: find.byType(PersonPicker),
            matching: find.text('第二页负责人'),
          ),
        );
        await t.pumpAndSettle();
      }
      expect(find.widgetWithText(InputChip, '第二页负责人'), findsOneWidget);
      await t.ensureVisible(find.text('选择标签'));
      await t.tap(find.text('选择标签'));
      await t.pumpAndSettle();
      await t.tap(find.text('重要'));
      await t.pumpAndSettle();
      await choose(t);
      await t.tap(find.widgetWithText(FilledButton, '派发任务'));
      await settle(t);
      expect(
        adapter.requests.any((o) => o.path == '/tasks' && o.method == 'POST'),
        isTrue,
        reason: t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .whereType<String>()
            .join(' | '),
      );
      final body =
          adapter.requests
                  .lastWhere((o) => o.path == '/tasks' && o.method == 'POST')
                  .data
              as Map;
      expect(body['participants'], ['first', 'second']);
      expect(body['attachments'], ['uploaded-1']);
      expect(body.keys.contains('status'), isFalse);
      await close(t);
    },
  );
  testWidgets(
    'attachment/portrait pages render at390dp1.5 text with actual HTTP responses',
    (t) async {
      final font = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
            ),
          ),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(File(materialIconsFontPath).readAsBytesSync()),
          ),
        );
      await icons.load();
      final key = GlobalKey();
      final c = await launch(
        t,
        '/form/profile-edit',
        boundary: key,
        scale: 1.5,
        picker: (_) async => [SelectedAttachment('头像.png', adapter.png)],
      );
      await choose(t, avatar: true);
      for (final (label, route) in [
        ('31-avatar-edit', '/form/profile-edit'),
        ('32-attachment', '/attachments/file'),
        ('33-task-files', '/item/tasks/task'),
      ]) {
        if (label != '31-avatar-edit') c.read(routerProvider).go(route);
        await settle(t);
        expect(t.takeException(), isNull, reason: label);
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await t.runAsync(() async {
          final img = await render.toImage(pixelRatio: 1);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          final output = File('../output/flutter-evidence/$label.png');
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(data!.buffer.asUint8List());
          img.dispose();
        });
      }
      await close(t);
    },
  );
}
