import 'package:dio/dio.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';

abstract interface class Repository {
  Future<PageResult> list(String resource, Query query);
  Future<Record> detail(String resource, String id);
  Future<Record> execute(String resource, Command command);
}

class HttpRepository implements Repository {
  HttpRepository(String baseUrl, String? token)
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
  final Dio dio;

  String _date(Query query) {
    final date = (query.from ?? DateTime.now()).toLocal();
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _period(Query query) {
    final span = query.to == null || query.from == null
        ? const Duration(days: 1)
        : query.to!.difference(query.from!);
    if (span.inDays >= 28) return 'month';
    if (span.inDays >= 7) return 'week';
    return 'day';
  }

  Map<String, dynamic> _query(Query query) => {
    if (query.cursor != null) 'cursor': query.cursor,
    if (query.ownerId != null) 'ownerId': query.ownerId,
    'limit': 30,
    if (query.search.isNotEmpty) 'search': query.search,
    if (query.from != null) 'date': _date(query),
    if (query.from != null) 'period': _period(query),
  };

  String _pathForList(String resource) => switch (resource) {
    'logs/subordinates' => '/logs/subordinates',
    'dashboard/company' => '/dashboard/company',
    'dashboard/personal' => '/dashboard/personal',
    'organization' || 'organization/admin' => '/organization/people',
    'audit' => '/organization/audit',
    'analytics' => '/analytics',
    'ai-maps' => '/ai-maps',
    _ => '/$resource',
  };

  Record _record(Map<String, dynamic> raw) {
    final fields = <String, dynamic>{};
    if (raw['fields'] is Map) {
      fields.addAll(Map<String, dynamic>.from(raw['fields'] as Map));
    }
    fields.addAll(raw);
    fields.removeWhere((key, _) => {
      'id', 'title', 'subtitle', 'ownerId', 'owner_id', 'version', 'fields'
    }.contains(key));
    if (raw['body'] is Map) fields.addAll(Map<String, dynamic>.from(raw['body'] as Map));
    if (raw.containsKey('owner_id')) fields['owner_id'] = raw['owner_id'];
    if (raw.containsKey('business_date')) fields['businessDate'] = raw['business_date'];
    if (raw.containsKey('created_at')) fields['createdAt'] = raw['created_at'];
    if (raw.containsKey('deadline')) fields['deadline'] = raw['deadline'];
    if (raw.containsKey('submitted')) fields['status'] = raw['submitted'] == true ? '已提交' : '草稿';
    final title = '${raw['title'] ?? raw['name'] ?? raw['business_date'] ?? '记录'}';
    final owner = '${raw['ownerId'] ?? raw['owner_id'] ?? raw['user_id'] ?? ''}';
    final version = raw['version'] is num ? (raw['version'] as num).toInt() : 1;
    return Record(
      id: '${raw['id'] ?? raw['object_id'] ?? title}',
      title: title,
      subtitle: '${raw['subtitle'] ?? raw['department_name'] ?? ''}',
      ownerId: owner,
      version: version,
      fields: fields,
    );
  }

  PageResult _page(dynamic data) {
    if (data is List) {
      return PageResult(data.map((item) => _record(Map<String, dynamic>.from(item as Map))).toList(), total: data.length);
    }
    final map = Map<String, dynamic>.from(data as Map);
    final rawItems = map['items'] is List
        ? map['items'] as List
        : map['nodes'] is List
        ? map['nodes'] as List
        : <dynamic>[];
    return PageResult(
      rawItems.map((item) => _record(Map<String, dynamic>.from(item as Map))).toList(),
      total: (map['total'] as num?)?.toInt() ?? rawItems.length,
      nextCursor: map['nextCursor']?.toString(),
    );
  }

  @override
  Future<PageResult> list(String resource, Query query) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        _pathForList(resource),
        queryParameters: _query(query),
      );
      return _page(response.data);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  @override
  Future<Record> detail(String resource, String id) async {
    try {
      final path = switch (resource) {
        'organization/profile' => '/profiles/${Uri.encodeComponent(id)}',
        'tasks' => '/tasks/${Uri.encodeComponent(id)}',
        'logs' || 'logs/subordinates' => '/logs/${Uri.encodeComponent(id)}',
        'reviews' => '/reviews/${Uri.encodeComponent(id)}',
        'ai-maps' => '/ai-maps',
        'private-notes' => '/private-notes',
        _ => '/$resource/${Uri.encodeComponent(id)}',
      };
      final response = await dio.get<dynamic>(path);
      if (resource == 'private-notes' || resource == 'ai-maps') {
        final page = _page(response.data);
        return page.items.firstWhere(
          (item) => item.id == id,
          orElse: () => throw const ApiFailure(FailureKind.notFound, '内容不存在或已被移除'),
        );
      }
      return _record(Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  Map<String, dynamic> _values(Command command) => {
    ...command.values,
  }..removeWhere((key, _) => key == 'id');

  Map<String, dynamic> _taskDraft(Command command) {
    final v = _values(command);
    return {
      'title': v['title'] ?? v['任务名称'],
      'ownerId': v['ownerId'],
      'deadline': v['deadline'],
      'group': v['所属分组'],
      'content': v['任务内容'] ?? v['内容'],
      'urgency': switch ('${v['紧急程度'] ?? '普通'}') {
        '紧急' => 'URGENT',
        '不紧急' => 'LOW',
        _ => 'NORMAL',
      },
      'progressNote': v['进度备注'],
      'collaborators': v['collaborators'] ??
          (v['协作人'] is String && '${v['协作人']}'.isNotEmpty ? ['${v['协作人']}'] : const <String>[]),
      'attachments': v['attachments'] ?? const <String>[],
    }..removeWhere((key, value) => value == null);
  }

  Future<Record> _postRecord(String path, Map<String, dynamic> body, {String? idempotencyKey}) async {
    final response = await dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: Options(headers: {if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey}),
    );
    return _record(response.data!);
  }

  @override
  Future<Record> execute(String resource, Command command) async {
    try {
      final v = _values(command);
      if (resource == 'auth') {
        final body = switch (command.action) {
          'login' => {'account': v['账号'], 'password': v['密码']},
          'register' => {'account': v['账号'], 'password': v['密码'], 'phone': v['手机号'], 'name': v['姓名'] ?? v['账号'], 'departmentId': v['departmentId'] ?? v['部门']},
          'password' => {'oldPassword': v['原密码'], 'newPassword': v['新密码']},
          'logout' => null,
          _ => throw const ApiFailure(FailureKind.unavailable, '后端未提供该认证操作'),
        };
        final response = command.action == 'logout'
            ? await dio.post<Map<String, dynamic>>('/auth/logout')
            : await dio.post<Map<String, dynamic>>('/auth/${command.action == 'password' ? 'password' : command.action}', data: body);
        final data = response.data ?? <String, dynamic>{};
        final user = data['user'] is Map ? Map<String, dynamic>.from(data['user'] as Map) : <String, dynamic>{};
        return _record({
          'id': user['id'] ?? data['id'] ?? 'auth',
          'title': user['name'] ?? '认证成功',
          'owner_id': user['id'],
          'fields': {'accessToken': data['token'], ...user, ...data},
        });
      }
      if (resource == 'tasks') {
        if (command.action == 'create') return _postRecord('/tasks', _taskDraft(command), idempotencyKey: command.idempotencyKey);
        final id = '${v['id'] ?? ''}';
        if (command.action == 'request-review') {
          return _postRecord('/tasks/$id/revisions', {'version': command.version ?? 1, 'reason': v['修改理由'] ?? v['reason'] ?? '', 'candidate': _taskDraft(command)});
        }
        final event = switch (command.action) {
          'receive' => 'RECEIVED',
          'feedback' => 'FEEDBACK',
          'accept' => 'ACCEPTED',
          'return' => 'FEEDBACK',
          'transfer' => 'TRANSFERRED',
          'reschedule' => 'RESCHEDULED',
          'withdraw' => 'WITHDRAWN',
          'archive' => 'ARCHIVED',
          _ => throw const ApiFailure(FailureKind.unavailable, '后端未提供该任务操作'),
        };
        return _postRecord('/tasks/$id/events', {
          'type': event,
          'version': command.version ?? 1,
          if (v['成果说明'] != null) 'text': v['成果说明'],
          if (v['验收意见'] != null) 'text': v['验收意见'],
          if (v['撤回原因'] != null) 'text': v['撤回原因'],
          if (v['ownerId'] != null) 'ownerId': v['ownerId'],
          if (v['deadline'] != null) 'deadline': v['deadline'],
        });
      }
      if (resource == 'logs') {
        if (command.action == 'request-review') {
          return _postRecord('/logs/${v['id']}/revisions', {'version': command.version ?? 1, 'reason': v['修改理由'] ?? '', 'body': {'work': v['今日工作'], 'blockers': v['遇到的阻碍'], 'tomorrow': v['明日计划'], 'hours': num.tryParse('${v['工时'] ?? 0}') ?? 0, 'taskIds': _ids(v['关联任务'])}});
        }
        if (command.action == 'submit') {
          var id = v['id']?.toString();
          if (id == null || id.isEmpty) {
            final draft = await _putRecord('/logs/draft', {'businessDate': v['businessDate'], 'body': {'work': v['今日工作'], 'blockers': v['遇到的阻碍'], 'tomorrow': v['明日计划'], 'hours': num.tryParse('${v['工时'] ?? 0}') ?? 0, 'taskIds': _ids(v['关联任务'])}, 'version': command.version ?? 0});
            id = draft.id;
          }
          final response = await dio.post<Map<String, dynamic>>('/logs/$id/submit', data: {'version': command.version ?? 1});
          return _record(response.data!);
        }
        return _putRecord('/logs/draft', {'businessDate': v['businessDate'], 'body': {'work': v['今日工作'], 'blockers': v['遇到的阻碍'], 'tomorrow': v['明日计划'], 'hours': num.tryParse('${v['工时'] ?? 0}') ?? 0, 'taskIds': _ids(v['关联任务'])}, 'version': command.version ?? 0});
      }
      if (resource == 'logs/comments') return _postRecord('/logs/${v['id']}/comments', {'text': v['评语'] ?? v['text']});
      if (resource == 'reviews') return _postRecord('/reviews/${v['id']}/decision', {'approve': command.action == 'approve', 'reason': v['reason'] ?? v['驳回原因'] ?? ''});
      if (resource == 'dashboard/personal') return _postRecord('/dashboard/personal', {'id': v['id'] ?? '', 'version': command.version ?? 0, 'title': v['title'] ?? v['标题'], 'text': v['内容'], 'position': int.tryParse('${v['排序位置'] ?? 0}') ?? 0, 'pinned': v['pinned'] ?? false, 'archived': command.action == 'archive'});
      if (resource == 'dashboard/company') return _postRecord('/dashboard/company/revisions', {...v, 'version': command.version ?? 0, 'reason': v['修改理由'] ?? v['reason'] ?? ''});
      if (resource == 'private-notes') return _putRecord('/private-notes', {'resource': v['resource'] ?? 'tasks', 'objectId': v['objectId'] ?? v['id'], 'text': v['备注'] ?? v['text'] ?? '', 'version': command.version ?? 0});
      if (resource == 'organization/profile') return _putRecord('/profiles/me', {'introduction': v['个人介绍'] ?? '', 'avatarAttachmentId': v['avatarAttachmentId'] ?? '', 'version': command.version ?? 1});
      if (resource == 'notifications') {
        final path = command.action == 'read-all' ? '/notifications/read-all' : '/notifications/${v['id']}/read';
        final response = await dio.post<Map<String, dynamic>>(path);
        return _record({'id': v['id'] ?? 'notifications', 'title': '操作成功', 'fields': response.data ?? {}});
      }
      if (resource == 'analytics/export') {
        final response = await dio.get<List<int>>(
          '/analytics/export',
          queryParameters: {
            'date': DateTime.now().toIso8601String().split('T').first,
            'period': 'week',
            'resource': 'logs',
          },
          options: Options(responseType: ResponseType.bytes),
        );
        return _record({
          'id': 'analytics-export',
          'title': '统计导出',
          'fields': {'bytes': response.data ?? const <int>[]},
        });
      }
      throw const ApiFailure(FailureKind.unavailable, '后端尚未提供该资源的写入接口');
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  List<String> _ids(dynamic value) => value is List
      ? value.map((item) => '$item').where((item) => item.isNotEmpty).toList()
      : (value == null || '$value'.isEmpty ? <String>[] : ['$value']);

  Future<Record> _putRecord(String path, Map<String, dynamic> body) async {
    final response = await dio.put<Map<String, dynamic>>(path, data: body);
    return _record(response.data!);
  }
}
