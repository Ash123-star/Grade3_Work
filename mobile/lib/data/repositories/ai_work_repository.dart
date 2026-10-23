import 'dart:math';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/ai_work.dart';
import 'package:pandora_mobile/data/sse_client.dart';

final workEventsProvider = StreamProvider.autoDispose
    .family<ServerEvent, String>((ref, id) async* {
      final client = ref.watch(sseClientProvider);
      if (client == null) return;
      final cursor = WorkEventCursor();
      final cancel = CancelToken();
      ref.onDispose(() => cancel.cancel());
      while (!cancel.isCancelled) {
        try {
          // 重连时重新鉴权恢复正文，即使没有新的持久事件。
          yield const ServerEvent('refresh', null, '{}');
          await for (final event in client.connect(
            '/ai/work-items/${Uri.encodeComponent(id)}/stream',
            lastEventId: cursor.value,
            cancel: cancel,
          )) {
            if (cancel.isCancelled) return;
            if (event.event == 'access-lost') {
              final status = workMap(jsonDecode(event.data))['status'];
              throw ApiFailure(
                status == 401
                    ? FailureKind.unauthorized
                    : status == 404
                    ? FailureKind.notFound
                    : FailureKind.forbidden,
                status == 401 ? '登录已失效，请重新登录' : '这件事已无法查看，请返回事项列表',
              );
            }
            if (event.event == 'refresh' || cursor.accept(event)) yield event;
          }
        } on ApiFailure catch (e) {
          if ([
            FailureKind.unauthorized,
            FailureKind.forbidden,
            FailureKind.notFound,
          ].contains(e.kind)) {
            rethrow;
          }
          if (e.code == 'INVALID_CURSOR') cursor.reset();
        }
        if (!cancel.isCancelled) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    });

/// 事件只触发 GET；游标单调递增，不用重放消息执行业务动作。
class WorkEventCursor {
  int _sequence = 0;
  String get value => '$_sequence';
  bool accept(ServerEvent event) {
    if (event.event != 'change') return false;
    final sequence = int.tryParse(event.id ?? '');
    if (sequence == null || sequence <= _sequence) return false;
    _sequence = sequence;
    return true;
  }

  void reset() => _sequence = 0;
}

final workRepositoryProvider = Provider<AiWorkRepository>((ref) {
  final session = ref.watch(sessionProvider);
  var alive = true;
  ref.onDispose(() => alive = false);
  return AiWorkRepository(
    ref.watch(httpRepositoryProvider).dio,
    isCurrent: () =>
        alive &&
        ref.read(sessionProvider).canReadBusiness &&
        ref.read(sessionProvider).id == session.id &&
        ref.read(sessionProvider).token == session.token,
  );
});
final workPageCountProvider = StateProvider.autoDispose<int>((ref) {
  ref.watch(sessionProvider);
  return 1;
});
final workListProvider = FutureProvider.autoDispose<WorkListPage>((ref) async {
  ref.watch(sessionProvider);
  final repository = ref.watch(workRepositoryProvider);
  final count = ref.watch(workPageCountProvider);
  final first = await repository.page(0);
  final byId = {for (final item in first.items) item.id: item};
  var next = first.nextCursor;
  for (var page = 1; page < count && next >= 0; page++) {
    final result = await repository.page(next);
    for (final item in result.items) {
      if (!byId.containsKey(item.id) || item.version > byId[item.id]!.version) {
        byId[item.id] = item;
      }
    }
    if (result.nextCursor <= next) {
      next = -1;
      break;
    }
    next = result.nextCursor;
  }
  return WorkListPage(byId.values.toList(), next);
});
final workCapabilitiesProvider = FutureProvider.autoDispose<WorkCapabilities>(
  (ref) => ref.watch(workRepositoryProvider).capabilities(),
);

class AiWorkRepository {
  AiWorkRepository(this.dio, {this.isCurrent});
  final Dio dio;
  final bool Function()? isCurrent;
  void _checkAccount() {
    if (isCurrent?.call() == false) {
      throw const ApiFailure(
        FailureKind.forbidden,
        '账号已切换，请重新打开事项',
        code: 'WORK_ACCOUNT_CHANGED',
      );
    }
  }

  T _parse<T>(T Function() decode) {
    try {
      return decode();
    } on FormatException {
      throw const ApiFailure(
        FailureKind.server,
        '暂时无法确认办理结果，请刷新后重试',
        code: 'WORK_INVALID_RESPONSE',
      );
    }
  }

  static String key() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? key,
  }) async {
    _checkAccount();
    try {
      final response = await dio.request<dynamic>(
        path,
        data: body,
        options: Options(
          method: method,
          receiveTimeout: const Duration(seconds: 90),
          headers: {'Idempotency-Key': ?key},
        ),
      );
      _checkAccount();
      if (response.data is! Map<String, dynamic>) {
        throw const ApiFailure(
          FailureKind.server,
          '暂时无法确认办理结果，请刷新后重试',
          code: 'WORK_INVALID_RESPONSE',
        );
      }
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  Future<WorkCapabilities> capabilities() async {
    final result = await request('GET', '/ai/work-capabilities');
    return _parse(() => WorkCapabilities.fromJson(result));
  }

  Future<List<WorkItem>> list() async => (await page(0)).items;
  Future<WorkListPage> page(int cursor) async {
    final result = await request(
      'GET',
      '/ai/work-items?cursor=$cursor&limit=30',
    );
    return _parse(() => WorkListPage.fromJson(result));
  }

  Future<WorkItem> get(String id) async {
    final result = await request(
      'GET',
      '/ai/work-items/${Uri.encodeComponent(id)}',
    );
    return _parse(() => WorkItem.fromJson(result, id: id));
  }

  Future<WorkItem> create(
    String text,
    List<String> files,
    String key, {
    String? taskId,
    int? taskVersion,
  }) async {
    final result = await request(
      'POST',
      '/ai/work-items',
      key: key,
      body: {
        'text': text,
        'attachmentIds': files,
        'taskId': ?taskId,
        'taskVersion': ?taskVersion,
      },
    );
    return _parse(() => WorkItem.fromJson(result));
  }

  Future<WorkItem> message(
    WorkItem item,
    String text,
    List<String> files,
    String key, {
    String? ownerId,
    String? taskId,
    int? taskVersion,
  }) async {
    final result = await request(
      'POST',
      '/ai/work-items/${Uri.encodeComponent(item.id)}/messages',
      key: key,
      body: {
        'version': item.version,
        'text': text,
        'attachmentIds': files,
        if (ownerId != null) 'answers': {'ownerId': ownerId},
        'taskId': ?taskId,
        'taskVersion': ?taskVersion,
      },
    );
    return _parse(() => WorkItem.fromJson(result, id: item.id));
  }

  Future<WorkItem> command(WorkItem item, String action, String key) async {
    if (!['cancel', 'retry'].contains(action)) {
      throw ArgumentError.value(action, 'action');
    }
    final result = await request(
      'POST',
      '/ai/work-items/${Uri.encodeComponent(item.id)}/$action',
      key: key,
      body: {'version': item.version},
    );
    return _parse(() => WorkItem.fromJson(result, id: item.id));
  }

  Future<WorkItem> confirm(WorkItem item, String key) async {
    final steps = workMaps(item.json['steps'])
        .where((s) => s['state'] == 'WAITING')
        .map((s) => '${s['step_key']}')
        .toList();
    final result = await request(
      'POST',
      '/ai/work-items/${Uri.encodeComponent(item.id)}/confirm',
      key: key,
      body: {
        'version': item.version,
        'planVersion': item.planVersion,
        'planHash': item.json['planHash'],
        'confirmationId': item.json['confirmationId'],
        'actions': steps,
      },
    );
    return _parse(() => WorkItem.fromJson(result, id: item.id));
  }

  Future<List<Map<String, dynamic>>> authorizations() async {
    _checkAccount();
    try {
      final response = await dio.get<dynamic>('/ai/work-authorizations');
      _checkAccount();
      if (response.data is! List ||
          (response.data as List).any((e) => e is! Map<String, dynamic>)) {
        throw const ApiFailure(
          FailureKind.server,
          '暂时无法读取授权，请重试',
          code: 'WORK_INVALID_RESPONSE',
        );
      }
      return workMaps(response.data);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  Future<void> delete(WorkItem item, String key) async {
    _checkAccount();
    try {
      final response = await dio.delete<dynamic>(
        '/ai/work-items/${Uri.encodeComponent(item.id)}',
        options: Options(
          headers: {'If-Match': '${item.version}', 'Idempotency-Key': key},
        ),
      );
      _checkAccount();
      _parse(() {
        final data = response.data;
        if (data is! Map ||
            data['id'] != item.id ||
            data['state'] != 'CANCELLED') {
          throw const FormatException('Missing deletion acknowledgement');
        }
      });
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }
}

String workError(Object error) {
  if (error is ApiFailure) {
    if (error.code == 'WORK_ACCOUNT_CHANGED') return '账号已切换，请重新打开事项';
    if (error.code == 'WORK_INVALID_RESPONSE') return '暂时无法确认办理结果，请刷新后重试';
    if (error.kind == FailureKind.unauthorized) return '登录已过期，请重新登录';
    if (error.kind == FailureKind.forbidden) return '你目前无法办理这项操作';
    if (error.kind == FailureKind.notFound) return '这件事已清除或暂时无法访问';
    if ([
      'VERSION_CONFLICT',
      'PLAN_STALE',
      'CHECK_STALE',
    ].contains(error.code)) {
      return '内容已更新，请刷新后再试';
    }
  }
  return '暂时没能处理，内容已保留，请稍后重试';
}
