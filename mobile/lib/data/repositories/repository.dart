import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/attachments.dart';
import 'package:pandora_mobile/data/models/diary_task_links.dart';
import 'complete_list.dart';

abstract interface class Repository {
  Future<PageResult> list(String resource, Query query);
  Future<Record> detail(String resource, String id, {String? ownerId});
  Future<Record> execute(String resource, Command command);
  Future<UploadedAttachment> uploadAttachment(
    SelectedAttachment file, {
    bool aiWork = false,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  });
  Future<DownloadedAttachment> downloadAttachment(
    String id, {
    CancelToken? cancelToken,
  });
}

class HttpRepository implements Repository {
  HttpRepository(
    String baseUrl,
    String? token, {
    void Function(ApiFailure)? onSessionFailure,
    bool businessAllowed = true,
  }) : dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 20),
           headers: {if (token != null) 'Authorization': 'Bearer $token'},
         ),
       ) {
    if (!businessAllowed) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.path.startsWith('/auth/')) {
              handler.next(request);
            } else {
              handler.reject(
                DioException(
                  requestOptions: request,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: request,
                    statusCode: 403,
                    data: const {'code': 'FORBIDDEN'},
                  ),
                ),
              );
            }
          },
        ),
      );
    }
    if (token != null && onSessionFailure != null) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) {
            final failure = ApiFailure.fromDio(error);
            final public = [
              '/auth/login',
              '/auth/register',
              '/auth/departments',
            ].contains(error.requestOptions.path);
            if (!public &&
                failure.code != 'INVALID_CREDENTIALS' &&
                (failure.kind == FailureKind.unauthorized ||
                    [
                      'PASSWORD_CHANGE_REQUIRED',
                      'MEMBERSHIP_PENDING',
                    ].contains(failure.code))) {
              onSessionFailure(failure);
            }
            handler.next(error);
          },
        ),
      );
    }
  }
  final Dio dio;

  Future<Response<T>> _getWithRetry<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    const backoff = [Duration(milliseconds: 300), Duration(milliseconds: 900)];
    for (var attempt = 0; ; attempt++) {
      try {
        return await dio.get<T>(path, queryParameters: queryParameters);
      } on DioException catch (error) {
        final transient =
            error.response?.statusCode == 503 ||
            const [
              DioExceptionType.connectionError,
              DioExceptionType.connectionTimeout,
              DioExceptionType.receiveTimeout,
              DioExceptionType.sendTimeout,
            ].contains(error.type);
        if (attempt >= backoff.length || !transient) rethrow;
        await Future<void>.delayed(backoff[attempt]);
      }
    }
  }

  @override
  Future<UploadedAttachment> uploadAttachment(
    SelectedAttachment file, {
    bool aiWork = false,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    file.validate();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/attachments',
        queryParameters: aiWork ? {'purpose': 'AI_WORK'} : null,
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            file.bytes,
            filename: safeAttachmentName(file.name),
          ),
        }),
        cancelToken: cancelToken,
        onSendProgress: onProgress,
      );
      final data = response.data;
      if (data == null ||
          data['id'] is! String ||
          (data['id'] as String).trim().isEmpty ||
          data['filename'] is! String ||
          data['size'] is! num ||
          (data['size'] as num).toInt() != file.bytes.length) {
        throw const ApiFailure(FailureKind.server, '上传响应不完整，文件未加入当前表单');
      }
      return UploadedAttachment(
        id: data['id'],
        name: safeAttachmentName(data['filename']),
        size: (data['size'] as num).toInt(),
      );
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  @override
  Future<DownloadedAttachment> downloadAttachment(
    String id, {
    CancelToken? cancelToken,
  }) async {
    if (id.trim().isEmpty) {
      throw const ApiFailure(FailureKind.validation, '附件标识无效');
    }
    try {
      final response = await dio.get<List<int>>(
        '/attachments/${Uri.encodeComponent(id)}',
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancelToken,
      );
      final bytes = response.data;
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > maximumAttachmentBytes) {
        throw const ApiFailure(FailureKind.server, '附件内容或大小无效');
      }
      final header = response.headers.value('content-disposition') ?? '';
      final encoded = RegExp(
        r"filename\*=UTF-8''([^;]+)",
        caseSensitive: false,
      ).firstMatch(header)?.group(1);
      final quoted = RegExp(
        r'filename="([^"]*)"',
        caseSensitive: false,
      ).firstMatch(header)?.group(1);
      final plain = RegExp(
        r'filename=([^;]+)',
        caseSensitive: false,
      ).firstMatch(header)?.group(1);
      var name = quoted ?? plain ?? 'attachment';
      if (encoded != null) {
        try {
          name = Uri.decodeComponent(encoded);
        } on FormatException {
          /* Use safe fallback below. */
        }
      }
      return DownloadedAttachment(
        name: safeAttachmentName(name),
        bytes: Uint8List.fromList(bytes),
      );
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  static const _taskPhases = {
    'DISPATCHED': '待接收',
    'REVISED': '待接收',
    'RECEIVED': '进行中',
    'FEEDBACK': '待验收',
    'ACCEPTED': '已验收',
    'ARCHIVED': '已归档',
    'WITHDRAWN': '已撤回',
  };
  static const _eventLabels = {
    'DISPATCHED': '派发任务',
    'REVISED': '审核生效，重新接收',
    'RECEIVED': '接收任务',
    'FEEDBACK': '提交成果反馈',
    'ACCEPTED': '验收任务',
    'ARCHIVED': '归档任务',
    'WITHDRAWN': '撤回任务',
    'TRANSFERRED': '转派任务',
    'RESCHEDULED': '调整截止时间',
  };

  Map<String, dynamic> _contentMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final parsed = jsonDecode(value);
        if (parsed is Map) return Map<String, dynamic>.from(parsed);
      } on FormatException {
        /* Plain text remains plain text. */
      }
    }
    return {};
  }

  String _date(Query query) {
    final date = shanghaiWallTime(query.from ?? DateTime.now());
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
    if (query.departmentId != null) 'departmentId': query.departmentId,
    'limit': 30,
    if (query.search.isNotEmpty) 'search': query.search,
    if (query.from != null) 'date': _date(query),
    if (query.from != null) 'period': _period(query),
  };

  String _pathForList(String resource) => switch (resource) {
    'tasks' => '/tasks',
    'logs' => '/logs',
    'logs/subordinates' => '/logs/subordinates',
    'dashboard/company' => '/dashboard/company',
    'dashboard/personal' => '/dashboard/personal',
    'organization' ||
    'organization/admin' ||
    'organization/dispatch-people' => '/organization/people',
    'audit' => '/organization/audit',
    'analytics' => '/analytics',
    'ai-maps' => '/ai-maps',
    'organization/departments' => '/organization/departments',
    'reviews' => '/reviews',
    'notifications' => '/notifications',
    _ => throw ApiFailure(FailureKind.unavailable, '列表接口尚未登记：$resource'),
  };

  Record _record(Map<String, dynamic> raw) {
    final fields = <String, dynamic>{};
    if (raw['fields'] is Map) {
      fields.addAll(Map<String, dynamic>.from(raw['fields'] as Map));
    }
    fields.addAll(raw);
    fields.removeWhere(
      (key, _) => {
        'id',
        'title',
        'subtitle',
        'ownerId',
        'owner_id',
        'version',
        'fields',
      }.contains(key),
    );
    fields.addAll(_contentMap(raw['body']));
    if (raw['profile'] is Map) {
      final profile = Map<String, dynamic>.from(raw['profile'] as Map);
      if (profile.containsKey('introduction')) {
        fields['个人介绍'] = profile['introduction'];
      }
      if (profile.containsKey('avatarAttachmentId')) {
        fields['avatarAttachmentId'] = profile['avatarAttachmentId'];
      }
      fields['姓名'] = raw['name'];
    }
    if (raw['department'] is Map) {
      fields['departmentName'] = raw['department']['name'];
      fields['departmentId'] = raw['department']['id'];
    } else if (raw['department'] != null) {
      fields['departmentName'] = raw['department'];
    }
    if (raw['author'] is Map) fields['authorName'] = raw['author']['name'];
    if (raw['kind'] != null && raw['target_id'] != null) {
      fields['targetId'] = raw['target_id'];
      fields['targetResource'] = switch (raw['kind']) {
        'LOG' => 'logs',
        'TASK' => 'tasks',
        'COMPANY_ITEM' => 'dashboard/company',
        'USER' || 'MEMBERSHIP' || 'REVIEWER' => 'organization',
        'POLICY' => 'organization/policy',
        'TEAM' => 'organization/teams',
        'DEPARTMENT' => 'organization/departments',
        _ => null,
      };
    }
    if (raw['type'] != null && raw['actor_id'] != null) {
      fields['auditType'] = '${raw['type']}'.startsWith('TASK')
          ? '任务'
          : '${raw['type']}'.startsWith('LOG')
          ? '日志'
          : '组织';
      fields['before_value'] = _contentMap(raw['before_value']);
      fields['after_value'] = _contentMap(raw['after_value']);
      fields['before'] = fields['before_value'];
      fields['after'] = fields['after_value'];
    }
    if (raw.containsKey('resource') && raw.containsKey('object_id')) {
      fields['备注'] = raw['text'] ?? '';
    }
    if (raw.containsKey('owner_id')) fields['owner_id'] = raw['owner_id'];
    if (raw.containsKey('business_date')) {
      fields['businessDate'] = raw['business_date'];
    }
    if (raw.containsKey('created_at')) fields['createdAt'] = raw['created_at'];
    if (raw['author'] is Map) {
      fields['authorName'] = (raw['author'] as Map)['name'];
    }
    if (raw.containsKey('submittedAt')) {
      fields['submittedAt'] = raw['submittedAt'];
    }
    if (raw.containsKey('submitted_at')) {
      fields['submittedAt'] = raw['submitted_at'];
    }
    if (raw.containsKey('deadline')) fields['deadline'] = raw['deadline'];
    if (raw.containsKey('start_at')) fields['startAt'] = raw['start_at'];
    if (raw.containsKey('startAt')) fields['startAt'] = raw['startAt'];
    if (raw.containsKey('tag_id')) fields['tagId'] = raw['tag_id'];
    if (raw.containsKey('tagId')) fields['tagId'] = raw['tagId'];
    if (raw.containsKey('tag_name')) fields['tagName'] = raw['tag_name'];
    if (raw.containsKey('tagName')) fields['tagName'] = raw['tagName'];
    if (raw.containsKey('tag_category')) {
      fields['tagCategory'] = raw['tag_category'];
    }
    if (raw.containsKey('tagCategory')) {
      fields['tagCategory'] = raw['tagCategory'];
    }
    if (raw.containsKey('tag_color')) fields['tagColor'] = raw['tag_color'];
    if (raw.containsKey('tagColor')) fields['tagColor'] = raw['tagColor'];
    if (raw['participant_ids'] is List) {
      fields['participantIds'] = raw['participant_ids'];
    }
    if (raw['participantIds'] is List) {
      fields['participantIds'] = raw['participantIds'];
    }
    if (raw['participants'] is List) {
      final values = raw['participants'] as List;
      fields['participantIds'] = [
        for (final value in values)
          value is Map ? '${value['id'] ?? value['user_id'] ?? ''}' : '$value',
      ].where((value) => value.isNotEmpty).toList();
      fields['participantNames'] = [
        for (final value in values)
          value is Map
              ? '${value['name'] ?? value['display_name'] ?? value['title'] ?? value['id'] ?? ''}'
              : '$value',
      ];
    }
    for (final pair in [
      ('work', '今日工作'),
      ('blockers', '遇到的阻碍'),
      ('tomorrow', '明日计划'),
      ('hours', '工时'),
      ('content', '任务内容'),
      ('text', '内容'),
      ('position', '排序位置'),
      ('group', '所属分组'),
      ('introduction', '个人介绍'),
      ('issuer_id', 'dispatcherId'),
      ('read_at', 'readAt'),
    ]) {
      if (fields.containsKey(pair.$1)) fields[pair.$2] = fields[pair.$1];
    }
    if (fields.containsKey('taskIds')) {
      fields['关联任务'] = DiaryTaskLinks.encode(fields['taskIds']);
    }
    if (fields['urgency'] != null) {
      fields['紧急程度'] = switch ('${fields['urgency']}') {
        'URGENT' => '紧急',
        'LOW' => '不紧急',
        _ => '普通',
      };
    }
    if (raw['phase'] != null) {
      fields['status'] = switch ('${raw['phase']}') {
        'DISPATCHED' => '待接收',
        'RECEIVED' => '进行中',
        'FEEDBACK' => '待验收',
        'ACCEPTED' => '已验收',
        'ARCHIVED' => '已归档',
        'WITHDRAWN' => '已撤回',
        _ => '${raw['phase']}',
      };
    }
    if (raw['events'] is List) {
      final events =
          (raw['events'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
            ..sort(
              (a, b) => (int.tryParse('${a['sequence']}') ?? 0).compareTo(
                int.tryParse('${b['sequence']}') ?? 0,
              ),
            );
      fields['events'] = [
        for (final e in events)
          '${e['actor_id'] ?? '操作者未提供'} · ${_eventLabels[e['type']] ?? '未知事件（${e['type']}）'} · ${e['created_at'] ?? '时间未提供'}',
      ];
      for (final e in events) {
        if (raw['phase'] == null && _taskPhases.containsKey(e['type'])) {
          fields['status'] = _taskPhases[e['type']];
        }
        final body = _contentMap(e['body']);
        if (e['type'] == 'REVISED') {
          fields.remove('成果说明');
          fields.remove('验收意见');
        }
        if (e['type'] == 'FEEDBACK') fields['成果说明'] = body['text'];
        if (e['type'] == 'ACCEPTED') fields['验收意见'] = body['text'];
      }
    }
    if (fields['attachments'] is List &&
        (fields['attachments'] as List).isNotEmpty) {
      fields['附件'] = '附件 ID：${(fields['attachments'] as List).join('、')}';
    }
    if (fields['collaborators'] is List &&
        (fields['collaborators'] as List).isNotEmpty) {
      fields['协作人'] = '成员 ID：${(fields['collaborators'] as List).join('、')}';
    }
    if (raw['applicant_id'] != null) {
      fields['reviewState'] = switch ('${raw['status']}') {
        'PENDING' => '待审',
        'APPROVED' => '已通过',
        'REJECTED' => '已驳回',
        _ => '${raw['status']}',
      };
      fields['before'] = raw['before_value'];
      fields['after'] = raw['candidate'];
      fields['baseVersion'] = raw['expected_version'];
      fields['steps'] = raw['steps'];
    }
    if (raw['read'] == null && raw.containsKey('read_at')) {
      fields['read'] = raw['read_at'] != null;
    }
    if (raw.containsKey('is_read')) fields['read'] = raw['is_read'] == true;
    if (raw.containsKey('recipient_id')) {
      fields['type'] = switch (raw['type']) {
        'TASK_ASSIGNED' || 'TASK_EVENT' || 'TASK_REVISED' => '任务',
        'DEADLINE' => '截止提醒',
        'LOG_SUBMITTED' => '日志',
        'LOG_COMMENT' => '评论',
        'REVIEW_PENDING' => '审批',
        'REVIEW_APPROVED' || 'REVIEW_REJECTED' => '审核结果',
        _ => '${raw['type'] ?? '消息'}',
      };
      final target = switch (raw['type']) {
        'TASK_ASSIGNED' ||
        'TASK_EVENT' ||
        'TASK_REVISED' ||
        'DEADLINE' => 'tasks',
        'LOG_SUBMITTED' || 'LOG_COMMENT' => 'logs',
        'REVIEW_PENDING' || 'REVIEW_APPROVED' || 'REVIEW_REJECTED' => 'reviews',
        _ => null,
      };
      if (target != null && raw['object_id'] != null) {
        fields['targetResource'] = target;
        fields['targetId'] = raw['object_id'];
      }
    }
    if (raw.containsKey('submitted')) {
      fields['status'] = raw['submitted'] == true ? '已提交' : '草稿';
    }
    final title =
        '${raw['title'] ?? raw['name'] ?? raw['business_date'] ?? (raw.containsKey('actor_id') ? raw['type'] : null) ?? (raw.containsKey('recipient_id') ? fields['type'] : null) ?? '记录'}';
    final owner =
        '${raw['ownerId'] ?? raw['owner_id'] ?? raw['user_id'] ?? raw['applicant_id'] ?? raw['recipient_id'] ?? ''}';
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
      return PageResult(
        data
            .map((item) => _record(Map<String, dynamic>.from(item as Map)))
            .toList(),
        total: data.length,
      );
    }
    final map = Map<String, dynamic>.from(data as Map);
    final rawItems = map['items'] is List
        ? map['items'] as List
        : map['nodes'] is List
        ? map['nodes'] as List
        : <dynamic>[];
    return PageResult(
      rawItems
          .map((item) => _record(Map<String, dynamic>.from(item as Map)))
          .toList(),
      total: (map['total'] as num?)?.toInt() ?? rawItems.length,
      nextCursor: map['nextCursor']?.toString(),
    );
  }

  @override
  Future<PageResult> list(String resource, Query query) async {
    try {
      if (resource == 'analytics') {
        final date = (query.from ?? DateTime.now())
            .toIso8601String()
            .split('T')
            .first;
        final summary = await detail('analytics', date, ownerId: 'week');
        return PageResult([summary], total: 1);
      }
      if (resource == 'auth/departments') {
        final response = await _getWithRetry<List<dynamic>>(
          '/auth/departments',
        );
        return _page(response.data ?? <dynamic>[]);
      }
      final response = await _getWithRetry<Map<String, dynamic>>(
        _pathForList(resource),
        queryParameters: {
          ..._query(query),
          if (resource == 'organization/dispatch-people') 'dispatch': true,
        },
      );
      return _page(response.data);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  @override
  Future<Record> detail(String resource, String id, {String? ownerId}) async {
    try {
      if (resource == 'organization/tree' ||
          resource == 'analytics' ||
          resource == 'organization/policy') {
        final path = switch (resource) {
          'organization/tree' => '/organization',
          'organization/policy' => '/organization/review-policy',
          _ => '/analytics',
        };
        final response = await _getWithRetry<Map<String, dynamic>>(
          path,
          queryParameters: resource == 'analytics'
              ? {'date': id, 'period': ownerId ?? 'week'}
              : null,
        );
        final raw = response.data!;
        if (resource == 'organization/tree') {
          final people = await readCompleteList(
            this,
            'organization',
            const Query(),
          );
          raw['people'] = people.items;
        }
        return _record({
          'id': resource,
          'title': '当前生效',
          ...raw,
          if (resource == 'organization/policy')
            'review_policy': _contentMap(raw['review_policy']),
        });
      }
      if (resource == 'dashboard/company' ||
          resource == 'dashboard/personal' ||
          resource == 'audit') {
        final page = await readCompleteList(
          this,
          resource,
          Query(ownerId: ownerId),
        );
        final match = page.items.where((r) => r.id == id).firstOrNull;
        if (match != null) return match;
        throw const ApiFailure(FailureKind.notFound, '该记录不存在或已不在可见范围');
      }
      final noteTarget = resource == 'private-notes'
          ? PrivateNoteTarget.parse(id)
          : null;
      if (resource == 'private-notes' &&
          (noteTarget == null || !noteTarget.supported)) {
        throw const ApiFailure(
          FailureKind.validation,
          '私人备注仅支持公司重点和任务，请从对应详情进入',
        );
      }
      final path = switch (resource) {
        'auth' => '/auth/me',
        'organization' ||
        'organization/profile' => '/profiles/${Uri.encodeComponent(id)}',
        'tasks' => '/tasks/${Uri.encodeComponent(id)}',
        'logs' || 'logs/subordinates' => '/logs/${Uri.encodeComponent(id)}',
        'reviews' => '/reviews/${Uri.encodeComponent(id)}',
        'ai-maps' => '/ai-maps',
        'private-notes' => '/private-notes',
        _ => throw ApiFailure(FailureKind.unavailable, '详情接口尚未登记：$resource'),
      };
      final response = await _getWithRetry<dynamic>(path);
      if (resource == 'private-notes' || resource == 'ai-maps') {
        final page = _page(response.data);
        return page.items.firstWhere(
          (item) => noteTarget == null
              ? item.id == id
              : item.fields['resource'] == noteTarget.resource &&
                    item.fields['object_id'] == noteTarget.objectId &&
                    item.ownerId == noteTarget.accountId,
          orElse: () =>
              throw const ApiFailure(FailureKind.notFound, '内容不存在或已被移除'),
        );
      }
      final raw = Map<String, dynamic>.from(response.data as Map);
      if ((resource == 'organization' || resource == 'organization/profile') &&
          raw['version'] is! num) {
        raw['version'] = 0;
      }
      if ((resource == 'logs' || resource == 'logs/subordinates') &&
          raw['submitted'] == true) {
        final results = await Future.wait([
          _diaryRelated(id, 'versions'),
          _diaryRelated(id, 'comments'),
        ]);
        for (var i = 0; i < results.length; i++) {
          final name = i == 0 ? 'versions' : 'comments';
          final result = results[i];
          if (result is ApiFailure) {
            if (result.kind == FailureKind.forbidden ||
                result.kind == FailureKind.unauthorized) {
              throw result;
            }
            raw['${name}Error'] = result;
          } else {
            raw[name] = result;
          }
        }
      }
      return _record(raw);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  Future<Object> _diaryRelated(String id, String kind) async {
    try {
      final response = await dio.get<List<dynamic>>(
        '/logs/${Uri.encodeComponent(id)}/$kind',
      );
      return [
        for (final value in response.data ?? [])
          if (value is Map)
            _diaryRelatedRecord(Map<String, dynamic>.from(value), kind),
      ];
    } on DioException catch (e) {
      return ApiFailure.fromDio(e);
    }
  }

  Map<String, dynamic> _diaryRelatedRecord(
    Map<String, dynamic> raw,
    String kind,
  ) {
    if (kind == 'comments') {
      return {
        'id': raw['id'],
        'parentCommentId': raw['parent_id'],
        'authorName': raw['author_name'],
        'text': raw['text'] ?? '',
        'actorId': raw['actor_id'],
        'parentId': raw['parent_id'],
        'time': raw['created_at'],
      };
    }
    final content = _contentMap(raw['body']);
    final record = _record({'id': '${raw['id']}', 'body': content});
    return {
      ...raw,
      'body': content['work'],
      'fields': record.fields,
      'time': raw['created_at'],
      'reason': raw['reason'],
    };
  }

  Map<String, dynamic> _values(Command command) =>
      {...command.values}..removeWhere((key, _) => key == 'id');

  String _commandId(Command command) {
    final id = command.values['id']?.toString();
    if (id == null || id.trim().isEmpty) {
      throw const ApiFailure(FailureKind.validation, '请选择需要操作的记录');
    }
    return id;
  }

  Map<String, dynamic> _diaryBody(Map<String, dynamic> v) => {
    'work': v['今日工作'] ?? '',
    'blockers': v['遇到的阻碍'] ?? '',
    'tomorrow': v['明日计划'] ?? '',
    'hours': num.tryParse('${v['工时'] ?? 0}') ?? 0,
    'taskIds': DiaryTaskLinks.parse(v['关联任务']),
  };

  Map<String, dynamic> _taskDraft(Command command) {
    final v = _values(command);
    // 已发布旧契约仍可读取和修订；新表单字段明确出现时保留新模型，不将多人静默降级。
    if (!v.containsKey('participantIds') &&
        !v.containsKey('参与人') &&
        !v.containsKey('tagId') &&
        !v.containsKey('标签')) {
      return {
        'title': v['title'] ?? v['任务名称'],
        'ownerId': v['ownerId'],
        'deadline': v['deadline'],
        'group': v['所属分组'] ?? v['group'] ?? '',
        'content': v['任务内容'] ?? v['内容'] ?? v['content'] ?? '',
        'urgency': switch ('${v['紧急程度'] ?? v['urgency'] ?? '普通'}') {
          '紧急' || 'URGENT' => 'URGENT',
          '不紧急' || 'LOW' => 'LOW',
          _ => 'NORMAL',
        },
        'progressNote': v['进度备注'] ?? v['progressNote'] ?? '',
        'collaborators': v['collaborators'] ?? const <String>[],
        'attachments': v['attachments'] ?? const <String>[],
      }..removeWhere((key, value) => value == null);
    }
    final tag = '${v['tagId'] ?? v['标签'] ?? ''}'.trim();
    final participants = v['participantIds'] ?? v['参与人'];
    return {
      'title': v['title'] ?? v['任务名称'],
      if (v['ownerId'] != null) 'ownerId': v['ownerId'],
      'participantIds': participants is List
          ? participants
          : '${participants ?? ''}'
                .split('、')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(),
      'startAt': v['startAt'],
      'deadline': v['deadline'],
      'content': v['任务内容'] ?? v['内容'] ?? v['content'],
      'urgency': switch ('${v['紧急程度'] ?? v['urgency'] ?? '普通'}') {
        '紧急' || 'URGENT' => 'URGENT',
        '不紧急' || 'LOW' => 'LOW',
        _ => 'NORMAL',
      },
      if (tag.isNotEmpty) 'tagId': tag,
      'attachments': v['attachments'] ?? const <String>[],
    }..removeWhere((key, value) => value == null);
  }

  Future<Record> _postRecord(
    String path,
    Map<String, dynamic> body, {
    String? idempotencyKey,
  }) async {
    final response = await dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: Options(headers: {'Idempotency-Key': ?idempotencyKey}),
    );
    return _record(response.data!);
  }

  @override
  Future<Record> execute(String resource, Command command) async {
    try {
      final v = {...command.values};
      if (resource == 'auth') {
        final body = switch (command.action) {
          'login' => {'account': v['账号'], 'password': v['密码']},
          'register' => {
            'account': v['账号'],
            'password': v['密码'],
            'phone': v['手机号'],
            'name': v['姓名'] ?? v['账号'],
            'departmentId': v['departmentId'] ?? v['部门'],
          },
          'password' => {'oldPassword': v['原密码'], 'newPassword': v['新密码']},
          'logout' => null,
          _ => throw const ApiFailure(FailureKind.unavailable, '后端未提供该认证操作'),
        };
        final response = command.action == 'logout'
            ? await dio.post<Map<String, dynamic>>('/auth/logout')
            : await dio.post<Map<String, dynamic>>(
                '/auth/${command.action == 'password' ? 'password' : command.action}',
                data: body,
              );
        final data = response.data ?? <String, dynamic>{};
        final user = data['user'] is Map
            ? Map<String, dynamic>.from(data['user'] as Map)
            : <String, dynamic>{};
        return _record({
          'id': user['id'] ?? data['id'] ?? 'auth',
          'title': user['name'] ?? '认证成功',
          'owner_id': user['id'],
          'fields': {'accessToken': data['token'], ...user, ...data},
        });
      }
      if (resource == 'tasks') {
        if (command.action == 'create') {
          return await _postRecord(
            '/tasks',
            _taskDraft(command),
            idempotencyKey: command.idempotencyKey,
          );
        }
        final id = Uri.encodeComponent(_commandId(command));
        if (command.action == 'return') {
          throw const ApiFailure(FailureKind.unavailable, '退回补充服务尚未接入，原任务未改变');
        }
        if (command.action == 'transfer' || command.action == 'reschedule') {
          final reason = '${v['变更理由'] ?? v['reason'] ?? ''}'.trim();
          if (reason.isEmpty || command.version == null) {
            throw const ApiFailure(FailureKind.validation, '请填写变更理由并读取当前版本');
          }
          if ((command.action == 'transfer' &&
                  '${v['ownerId'] ?? ''}'.trim().isEmpty) ||
              (command.action == 'reschedule' &&
                  '${v['deadline'] ?? ''}'.trim().isEmpty)) {
            throw const ApiFailure(FailureKind.validation, '请填写候选负责人或截止时间');
          }
          final current = await detail('tasks', _commandId(command));
          if (current.version != command.version) {
            throw const ApiFailure(FailureKind.conflict, '任务已有新版本，请重新读取后再申请修改');
          }
          final candidate = _taskDraft(
            Command('create', {
              ...current.fields,
              'title': current.title,
              'ownerId': current.ownerId,
              if (command.action == 'transfer') 'ownerId': v['ownerId'],
              if (command.action == 'reschedule') 'deadline': v['deadline'],
            }),
          );
          return await _postRecord('/tasks/$id/revisions', {
            'version': command.version,
            'reason': reason,
            'candidate': candidate,
          });
        }
        if (command.action == 'request-review') {
          return await _postRecord('/tasks/$id/revisions', {
            'version': command.version ?? 1,
            'reason': v['修改理由'] ?? v['reason'] ?? '',
            'candidate': _taskDraft(command),
          });
        }
        final event = switch (command.action) {
          'receive' => 'RECEIVED',
          'feedback' => 'FEEDBACK',
          'accept' => 'ACCEPTED',
          'withdraw' => 'WITHDRAWN',
          'archive' => 'ARCHIVED',
          _ => throw const ApiFailure(FailureKind.unavailable, '后端未提供该任务操作'),
        };
        return await _postRecord('/tasks/$id/events', {
          'type': event,
          'version': command.version ?? 1,
          if (v['成果说明'] != null)
            'text':
                '${v['成果说明']}${'${v['遇到的阻碍'] ?? ''}'.trim().isEmpty ? '' : '\n\n遇到的阻碍：${v['遇到的阻碍']}'}',
          if (v['验收意见'] != null) 'text': v['验收意见'],
          if (v['撤回原因'] != null) 'text': v['撤回原因'],
          if (v['ownerId'] != null) 'ownerId': v['ownerId'],
          if (v['deadline'] != null) 'deadline': v['deadline'],
        });
      }
      if (resource == 'logs') {
        if (command.action == 'withdraw') {
          return await _postRecord(
            '/logs/${Uri.encodeComponent(_commandId(command))}/withdraw',
            {
              'version': command.version,
              'reason': v['reason'] ?? v['撤回原因'] ?? '',
            },
          );
        }
        if (command.action == 'read') {
          final id = _commandId(command);
          final response = await dio.post<dynamic>(
            '/logs/${Uri.encodeComponent(id)}/read',
            data: <String, dynamic>{},
          );
          if (response.data is! Map || (response.data as Map)['ok'] != true) {
            throw const ApiFailure(FailureKind.server, '服务器未确认阅读登记，请重试');
          }
          return Record(id: id, title: '阅读已登记', fields: const {'ok': true});
        }
        if (command.action == 'withdraw') {
          return await _postRecord(
            '/logs/${Uri.encodeComponent(_commandId(command))}/withdraw',
            {'version': command.version, 'reason': v['撤回原因']},
          );
        }
        if (command.action == 'request-review') {
          return await _postRecord(
            '/logs/${Uri.encodeComponent(_commandId(command))}/revisions',
            {
              'version': command.version ?? 1,
              'reason': v['修改理由'] ?? '',
              'body': _diaryBody(v),
            },
          );
        }
        if (command.action == 'submit') {
          var id = v['id']?.toString();
          var submitVersion = command.version;
          if (id == null || id.isEmpty || v.containsKey('今日工作')) {
            if ('${v['businessDate'] ?? ''}'.isEmpty) {
              throw const ApiFailure(FailureKind.validation, '请选择日报业务日期');
            }
            final draft = await _putRecord('/logs/draft', {
              'businessDate': v['businessDate'],
              'body': _diaryBody(v),
              'version': command.version ?? 0,
            });
            id = draft.id;
            submitVersion = draft.version;
          }
          try {
            final response = await dio.post<Map<String, dynamic>>(
              '/logs/${Uri.encodeComponent(id)}/submit',
              data: {'version': submitVersion ?? 1},
            );
            return _record(response.data!);
          } on DioException catch (e) {
            throw DiarySubmitFailure(
              ApiFailure.fromDio(e),
              id,
              submitVersion ?? 1,
            );
          }
        }
        if (command.action == 'update') {
          throw const ApiFailure(
            FailureKind.unavailable,
            '已提交日志修改接口尚未定案；当前不会误写入草稿',
          );
        }
        return await _putRecord('/logs/draft', {
          'businessDate': v['businessDate'],
          'body': _diaryBody(v),
          'version': command.version ?? 0,
        });
      }
      if (resource == 'logs/comments') {
        return await _postRecord(
          '/logs/${Uri.encodeComponent(_commandId(command))}/comments',
          {
            'text': v['评语'] ?? v['text'],
            if (v['parentCommentId'] != null || v['parentId'] != null)
              'parentId': v['parentCommentId'] ?? v['parentId'],
          },
        );
      }
      if (resource == 'reviews') {
        return await _postRecord(
          '/reviews/${Uri.encodeComponent(_commandId(command))}/decision',
          {
            'approve': command.action == 'approve',
            'reason': v['reason'] ?? v['驳回原因'] ?? '',
          },
        );
      }
      if (resource == 'dashboard/personal') {
        return await _postRecord('/dashboard/personal', {
          'id': v['id'] ?? '',
          'version': command.version ?? 0,
          'title': v['title'] ?? v['标题'],
          'text': v['内容'],
          'position': int.tryParse('${v['排序位置'] ?? 0}') ?? 0,
          'pinned': v['pinned'] ?? false,
          'archived': command.action == 'archive',
        });
      }
      if (resource == 'dashboard/company') {
        return await _postRecord('/dashboard/company/revisions', {
          'id': v['id'] ?? '',
          'title': v['title'] ?? v['标题'],
          'text': v['内容'] ?? v['text'] ?? '',
          'pinned': v['pinned'] ?? false,
          'archived': v['archived'] ?? false,
          'position': int.tryParse('${v['排序位置'] ?? v['position'] ?? 0}') ?? 0,
          'version': command.version ?? 0,
          'reason': v['修改理由'] ?? v['reason'] ?? '',
        });
      }
      if (resource == 'private-notes') {
        final target = PrivateNoteTarget.parse('${command.values['id'] ?? ''}');
        if (target == null || !target.supported) {
          throw const ApiFailure(
            FailureKind.validation,
            '私人备注仅支持公司重点和任务，请从对应详情进入',
          );
        }
        return await _putRecord('/private-notes', {
          'resource': target.resource,
          'objectId': target.objectId,
          'text': v['备注'] ?? v['text'] ?? '',
          'version': command.version ?? 0,
        });
      }
      if (resource == 'organization/profile') {
        return await _putRecord('/profiles/me', {
          'introduction': v['个人介绍'] ?? '',
          if (v.containsKey('avatarAttachmentId'))
            'avatarAttachmentId': v['avatarAttachmentId'],
          'version': command.version ?? 1,
        });
      }
      if (resource == 'notifications') {
        final path = command.action == 'read-all'
            ? '/notifications/read-all'
            : '/notifications/${Uri.encodeComponent(_commandId(command))}/read';
        final response = await dio.post<Map<String, dynamic>>(path);
        return _record({
          'id': v['id'] ?? 'notifications',
          'title': '操作成功',
          'fields': response.data ?? {},
        });
      }
      if (resource == 'organization/admin') {
        final reason = '${v['reason'] ?? ''}'.trim();
        if (reason.isEmpty || command.version == null) {
          throw const ApiFailure(FailureKind.validation, '请确认当前版本并填写变更理由');
        }
        if (command.action == 'unit') {
          final kind = '${v['kind']}';
          if ((v['id'] == null || '${v['id']}'.isEmpty) &&
                  command.version != 0 ||
              '${v['id'] ?? ''}'.isNotEmpty && command.version! < 1) {
            throw const ApiFailure(
              FailureKind.validation,
              '新增组织使用版本0，修改需读取实际版本',
            );
          }
          if (!['departments', 'teams'].contains(kind) ||
              '${v['name'] ?? ''}'.trim().isEmpty ||
              kind == 'teams' && '${v['departmentId'] ?? ''}'.isEmpty) {
            throw const ApiFailure(FailureKind.validation, '请填写组织名称并选择实际部门');
          }
          return await _postRecord('/organization/$kind/revisions', {
            'id': v['id'] ?? '',
            'name': v['name'],
            if (kind == 'teams') 'departmentId': v['departmentId'],
            'version': command.version,
            'reason': reason,
          });
        }
        if (command.action == 'policy') {
          if (command.version! < 1) {
            throw const ApiFailure(FailureKind.validation, '请读取当前审核策略版本');
          }
          if (v['taskTeamReview'] is! bool ||
              v['taskDepartmentReview'] is! bool) {
            throw const ApiFailure(FailureKind.validation, '请选择有效的审核策略开关');
          }
          return await _postRecord('/organization/review-policy/revisions', {
            'version': command.version,
            'reason': reason,
            'taskTeamReview': v['taskTeamReview'],
            'taskDepartmentReview': v['taskDepartmentReview'],
          });
        }
        if (command.action == 'user') {
          if (command.version! < 1) {
            throw const ApiFailure(FailureKind.validation, '请读取当前成员版本');
          }
          final allowed = {
            'name',
            'departmentId',
            'teamId',
            'role',
            'status',
            'dispatchEnabled',
            'companyReviewer',
            'managerId',
          };
          if (v.containsKey('role') &&
                  ![
                    'ADMIN',
                    'FOUNDER',
                    'DIRECTOR',
                    'LEADER',
                    'EMPLOYEE',
                  ].contains(v['role']) ||
              v.containsKey('status') &&
                  !['ACTIVE', 'DISABLED'].contains(v['status']) ||
              [
                'dispatchEnabled',
                'companyReviewer',
              ].any((k) => v.containsKey(k) && v[k] is! bool)) {
            throw const ApiFailure(FailureKind.validation, '角色、状态或权限开关无效');
          }
          return await _postRecord(
            '/organization/users/${Uri.encodeComponent(_commandId(command))}/revisions',
            {
              for (final key in allowed)
                if (v.containsKey(key)) key: v[key],
              'version': command.version,
              'reason': reason,
            },
          );
        }
      }
      if (resource == 'analytics/export') {
        final date = '${v['date'] ?? ''}',
            period = '${v['period'] ?? ''}',
            target = '${v['resource'] ?? ''}';
        if (DateTime.tryParse(date) == null ||
            !['day', 'week', 'month'].contains(period) ||
            !['logs', 'tasks'].contains(target)) {
          throw const ApiFailure(FailureKind.validation, '请指定导出业务日期、周期和记录类型');
        }
        final response = await dio.get<List<int>>(
          '/analytics/export',
          queryParameters: {'date': date, 'period': period, 'resource': target},
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

  Future<Record> _putRecord(String path, Map<String, dynamic> body) async {
    final response = await dio.put<Map<String, dynamic>>(path, data: body);
    return _record(response.data!);
  }
}
