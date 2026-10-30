import 'dart:convert';
import 'dart:typed_data';
import 'package:pandora_mobile/data/models/task_display.dart';
import 'package:pandora_mobile/data/models/record_display.dart';
import 'package:pandora_mobile/data/models/notification_display.dart';
import 'package:dio/dio.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/attachments.dart';
import 'package:pandora_mobile/data/models/diary_task_links.dart';
import 'complete_list.dart';

abstract interface class Repository {
  Future<PageResult> list(String resource, Query query);
  Future<MemberLogMonth> memberLogMonth(String ownerId, DateTime month);
  Future<Record> detail(String resource, String id, {String? ownerId});
  Future<Record> analytics(AnalyticsQuery query);
  Future<PageResult> analyticsDetails(AnalyticsDetailsQuery query);
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
    'RETURNED': '需补充',
    'ACCEPTED': '已验收',
    'ARCHIVED': '已归档',
    'WITHDRAWN': '已撤回',
  };
  static const _eventLabels = {
    'DISPATCHED': '派发任务',
    'REVISED': '审核生效，重新接收',
    'RECEIVED': '接收任务',
    'FEEDBACK': '提交成果反馈',
    'RETURNED': '退回补充',
    'ACCEPTED': '验收任务',
    'ARCHIVED': '归档任务',
    'WITHDRAWN': '撤回任务',
    'TRANSFERRED': '转派任务',
    'REASSIGNED': '转派任务',
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

  Map<String, dynamic> _query(Query query, {String? resource}) => {
    if (query.cursor != null) 'cursor': query.cursor,
    if (query.ownerId != null)
      (resource == 'tasks' ? 'participantId' : 'ownerId'): query.ownerId,
    if (query.departmentId != null) 'departmentId': query.departmentId,
    'limit': 30,
    if (query.search.isNotEmpty) 'search': query.search,
    if (query.from != null) 'date': _date(query),
    if (query.from != null) 'period': _period(query),
  };

  String _pathForList(String resource) => switch (resource) {
    'tasks/received-card' => '/tasks/received-card',
    'tasks' => '/tasks',
    'task-labels' => '/task-labels',
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
    'organization/teams' => '/organization/teams',
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
      for (final key in ['phone', 'email', 'gender', 'age']) {
        if (!raw.containsKey(key) && profile.containsKey(key)) {
          fields[key] = profile[key];
        }
      }
      fields['姓名'] = raw['name'];
    }
    if (raw['department'] is Map) {
      fields['departmentName'] = raw['department']['name'];
      fields['departmentId'] = raw['department']['id'];
    } else if (raw['department'] != null) {
      fields['departmentName'] = raw['department'];
    }
    if (raw['department_name'] != null) fields['departmentName'] = raw['department_name'];
    if (raw['team'] is Map) {
      fields['teamName'] = raw['team']['name'];
      fields['teamId'] = raw['team']['id'];
    } else if (raw['team_name'] != null) {
      fields['teamName'] = raw['team_name'];
    }
    if (raw['author'] is Map) fields['authorName'] = raw['author']['name'];
    if (raw['kind'] != null && raw['target_id'] != null) {
      fields['targetId'] = raw['target_id'];
      fields['targetResource'] = '${raw['kind']}'.startsWith('TASK')
          ? 'tasks'
          : switch (raw['kind']) {
              'LOG' => 'logs',
              'COMPANY_ITEM' => 'dashboard/company',
              'USER' || 'MEMBERSHIP' || 'REVIEWER' => 'organization',
              'POLICY' => 'organization/policy',
              'TEAM' => 'organization/teams',
              'DEPARTMENT' => 'organization/departments',
              _ => null,
            };
      fields['reviewKind'] = raw['kind'];
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
    final dispatchAt =
        raw['dispatchAt'] ??
        raw['dispatched_at'] ??
        raw['dispatch_at'] ??
        fields['dispatched_at'] ??
        fields['dispatch_at'];
    if (dispatchAt != null) fields['dispatchAt'] = dispatchAt;
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
    if (raw['label'] is Map) {
      final label = Map<String, dynamic>.from(raw['label'] as Map);
      fields['tagId'] = label['id'];
      fields['tagName'] = label['name'];
      fields['tagCategory'] = label['category'];
      fields['tagColor'] = label['color'];
    }
    if (raw['participant_ids'] is List) {
      fields['participantIds'] = raw['participant_ids'];
    }
    if (raw['participantIds'] is List) {
      fields['participantIds'] = raw['participantIds'];
    }
    if (fields['participant_names'] is List &&
        fields['participantNames'] is! List) {
      fields['participantNames'] = fields['participant_names'];
    }
    if (raw['participants'] is List) {
      final values = (raw['participants'] as List).indexed.where((entry) {
        final value = entry.$2;
        final id = value is Map
            ? value['id'] ?? value['user_id'] ?? value['userId']
            : value;
        return id != null && '$id'.trim().isNotEmpty;
      }).toList();
      final existingNames = fields['participantNames'] is List
          ? fields['participantNames'] as List
          : const [];
      final existingIds = fields['participantIds'] ?? fields['participant_ids'];
      final namesById = <String, dynamic>{
        if (existingIds is List)
          for (
            var i = 0;
            i < existingIds.length && i < existingNames.length;
            i++
          )
            '${existingIds[i]}'.trim(): existingNames[i],
      };
      String fallbackName(String id, int originalIndex) =>
          '${namesById[id] ?? (existingIds is! List && originalIndex < existingNames.length ? existingNames[originalIndex] : '')}';
      fields['participantIds'] = [
        for (final (_, value) in values)
          value is Map
              ? '${value['id'] ?? value['user_id'] ?? value['userId']}'
              : '$value',
      ];
      fields['participantNames'] = [
        for (final (index, value) in values)
          value is Map
              ? '${value['name'] ?? value['display_name'] ?? value['displayName'] ?? value['title'] ?? fallbackName('${value['id'] ?? value['user_id'] ?? value['userId']}'.trim(), index)}'
              : fallbackName('$value'.trim(), index),
      ];
    }
    if (fields.containsKey('tagId') ||
        fields.containsKey('tagName') ||
        fields.containsKey('tag_id') ||
        fields.containsKey('tag_name')) {
      fields['tagName'] = taskTagLabel(fields);
    }
    if (fields['participantIds'] is List ||
        fields['participantNames'] is List) {
      fields['participantNames'] = taskParticipantNames(fields);
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
    final taskResponse = raw.containsKey('issuer_id');
    if (!taskResponse && raw['phase'] != null) {
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
          '${displayPersonName(e['actor_name'])} · ${_eventLabels[e['type']] ?? '未知事件（${e['type']}）'} · ${e['created_at'] ?? '时间未提供'}',
      ];
      for (final e in events) {
        if (e['type'] == 'DISPATCHED' && e['created_at'] != null) {
          fields['dispatchAt'] = e['created_at'];
        }
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
        'SUPERSEDED' => '已失效',
        _ => '${raw['status']}',
      };
      fields['before'] = raw['before_value'];
      fields['after'] = raw['candidate'];
      fields['displayReferences'] = raw['display_references'];
      fields['baseVersion'] = raw['expected_version'];
      fields['steps'] = raw['steps'];
      fields['reviewEvents'] = [
        for (final step in (raw['steps'] as List? ?? const []).whereType<Map>())
          '${displayPersonName(step['reviewer_name'])} · ${switch (step['state']) {
            'APPROVED' => '审核通过',
            'REJECTED' => '驳回',
            'SUPERSEDED' => '已失效',
            _ => '待审核',
          }}${'${step['reason'] ?? ''}'.trim().isEmpty ? '' : ' · ${step['reason']}'}${step['decided_at'] == null ? '' : ' · ${step['decided_at']}'}',
      ];
      fields['applicantId'] = raw['applicant_id'];
      fields['applicantName'] =
          raw['applicant_name'] ?? (raw['applicant'] is Map ? raw['applicant']['name'] : null);
      fields['reviewerId'] = raw['reviewer_id'];
      fields['reviewerName'] =
          raw['reviewer_name'] ?? (raw['reviewer'] is Map ? raw['reviewer']['name'] : null);
      fields['reviewerConfigured'] = raw.containsKey('reviewer_configured')
          ? raw['reviewer_configured'] == true
          : fields['reviewerId'] != null;
      fields['approvalMode'] = raw['approval_mode'] ?? 'DIRECT_MANAGER';
      fields['decisionSource'] = raw['decision_source'];
    }
    if (raw['read'] == null && raw.containsKey('read_at')) {
      fields['read'] = raw['read_at'] != null;
    }
    if (raw.containsKey('is_read')) fields['read'] = raw['is_read'] == true;
    if (raw.containsKey('recipient_id')) {
      fields['type'] = notificationTitle(raw['type']);
      final target = notificationResource(raw['type']);
      if (target != null && raw['object_id'] != null) {
        fields['targetResource'] = target;
        fields['targetId'] = raw['object_id'];
      }
    }
    if (raw.containsKey('submitted')) {
      fields['status'] = raw['submitted'] == true ? '已提交' : '草稿';
    }
    final taskReview = '${raw['kind'] ?? ''}'.startsWith('TASK');
    final title = raw.containsKey('recipient_id')
        ? notificationTitle(raw['type'])
        : raw.containsKey('business_date') || raw.containsKey('businessDate')
        ? workLogTitle(fields, explicitTitle: raw['title'])
        : '${raw['title'] ?? raw['name'] ?? (taskReview ? '任务审核申请' : null) ?? (raw.containsKey('actor_id') ? raw['type'] : null) ?? (raw.containsKey('recipient_id') ? fields['type'] : null) ?? '记录'}';
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
      final parameters = _query(query, resource: resource);
      if (resource == 'tasks' &&
          query.from != null &&
          query.to != null) {
        parameters
          ..remove('date')
          ..remove('period')
          ..['from'] = query.from!.toUtc().toIso8601String()
          ..['to'] = query.to!.toUtc().toIso8601String();
      }
      if (resource == 'logs/subordinates' &&
          query.from != null &&
          query.to != null) {
        parameters
          ..remove('date')
          ..remove('period')
          ..['from'] = query.from!.toUtc().toIso8601String()
          ..['to'] = query.to!.toUtc().toIso8601String();
      }
      final response = await _getWithRetry<Map<String, dynamic>>(
        _pathForList(resource),
        queryParameters: {
          ...parameters,
          if (resource == 'organization/dispatch-people') 'dispatch': true,
        },
      );
      return _page(response.data);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  @override
  Future<MemberLogMonth> memberLogMonth(String ownerId, DateTime month) async {
    try {
      final response = await _getWithRetry<dynamic>(
        '/logs/subordinates/calendar',
        queryParameters: {
          'ownerId': ownerId,
          'month':
              '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}',
        },
      );
      final result = MemberLogMonth.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      if (result.ownerId != ownerId ||
          result.month.year != month.year ||
          result.month.month != month.month) {
        throw const ApiFailure(
          FailureKind.unavailable,
          '成员日志日历响应范围不匹配',
        );
      }
      return result;
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
    }
  }

  @override
  Future<Record> analytics(AnalyticsQuery query) async {
    try {
      final response = await _getWithRetry<Map<String, dynamic>>(
        '/analytics',
        queryParameters: query.toJson(),
      );
      return _record(response.data!);
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
    }
  }

  @override
  Future<PageResult> analyticsDetails(AnalyticsDetailsQuery query) async {
    try {
      final response = await _getWithRetry<Map<String, dynamic>>(
        '/analytics/details',
        queryParameters: query.toJson(),
      );
      final data = response.data!;
      return PageResult(
        (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => _record(Map<String, dynamic>.from(item)))
            .toList(),
        total: (data['total'] as num?)?.toInt() ?? 0,
        nextCursor: '${data['nextCursor'] ?? ''}'.isEmpty
            ? null
            : '${data['nextCursor']}',
      );
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
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
      if (resource == 'tasks') {
        final result = await _taskComments(id);
        if (result is ApiFailure) {
          if (result.kind == FailureKind.forbidden ||
              result.kind == FailureKind.unauthorized ||
              result.kind == FailureKind.notFound) {
            throw result;
          }
          raw['commentsError'] = result;
        } else {
          raw['comments'] = result;
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
        'actorName': displayPersonName(raw['author_name']),
        'authorName': displayPersonName(raw['author_name']),
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

  Future<Object> _taskComments(String id) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/tasks/${Uri.encodeComponent(id)}/comments',
      );
      final items = response.data?['items'];
      if (items is! List) {
        throw const ApiFailure(FailureKind.server, '服务器返回的任务评论格式无效');
      }
      return [
        for (final value in items)
          if (value is Map)
            _taskCommentRecord(Map<String, dynamic>.from(value)),
      ];
    } on DioException catch (e) {
      return ApiFailure.fromDio(e);
    }
  }

  Map<String, dynamic> _taskCommentRecord(Map<String, dynamic> raw) => {
    'id': raw['id'],
    'parentCommentId': raw['parent_id'],
    'actorId': raw['author_id'],
    'actorName': displayPersonName(raw['nickname']),
    'avatarId': raw['avatar_id'],
    'text': raw['body'] ?? '',
    'createdAt': raw['created_at'],
    'time': raw['created_at'],
  };

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
    'work': v['今日工作'] ?? v['work'] ?? '',
  };

  Map<String, dynamic> _taskDraft(Command command) {
    final v = _values(command);
    final labelId = '${v['tagId'] ?? v['labelId'] ?? v['标签'] ?? ''}'.trim();
    final participantValues =
        v['participantIds'] ?? v['participants'] ?? v['参与人'];
    final participants = participantValues is List
        ? participantValues.map((value) => '$value'.trim())
        : '${participantValues ?? ''}'.split('、').map((value) => value.trim());
    final normalizedParticipants = <String>{
      for (final value in participants)
        if (value.isNotEmpty) value,
    }.toList();
    if (normalizedParticipants.isEmpty) {
      throw const ApiFailure(FailureKind.validation, '至少选择一名任务参与人');
    }
    return {
      'title': v['title'] ?? v['任务名称'],
      'participants': normalizedParticipants,
      'startAt': v['startAt'],
      'deadline': v['deadline'],
      'group': v['所属分组'] ?? v['group'],
      'content': v['任务内容'] ?? v['内容'] ?? v['content'],
      'urgency': switch ('${v['紧急程度'] ?? v['urgency'] ?? '普通'}') {
        '紧急' || 'URGENT' => 'URGENT',
        '不紧急' || 'LOW' => 'LOW',
        _ => 'NORMAL',
      },
      if (labelId.isNotEmpty) 'labelId': labelId,
      'attachments': v['attachments'] ?? const <String>[],
    }..removeWhere((key, value) => value == null);
  }

  Map<String, dynamic> _taskLabelDraft(Command command) {
    final v = _values(command);
    return {
      'name': v['name'] ?? v['名称'],
      'category': v['category'] ?? v['分类'],
      'color': v['color'] ?? v['颜色'],
      if ((v['departmentId'] ?? v['部门']) != null)
        'departmentId': v['departmentId'] ?? v['部门'],
      if (v['status'] != null) 'status': v['status'],
      if (command.version != null) 'version': command.version,
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
        if (command.action == 'transfer' || command.action == 'reschedule') {
          final reason = '${v['变更理由'] ?? v['reason'] ?? ''}'.trim();
          if (reason.isEmpty || command.version == null) {
            throw const ApiFailure(FailureKind.validation, '请填写变更理由并读取当前版本');
          }
          final transferParticipants =
              v['participantIds'] ?? v['participants'] ?? v['参与人'];
          if ((command.action == 'transfer' &&
                  transferParticipants is! List &&
                  '${transferParticipants ?? v['ownerId'] ?? ''}'
                      .trim()
                      .isEmpty) ||
              (command.action == 'reschedule' &&
                  '${v['deadline'] ?? ''}'.trim().isEmpty)) {
            throw const ApiFailure(FailureKind.validation, '请填写候选参与人或截止时间');
          }
          final current = await detail('tasks', _commandId(command));
          if (current.version != command.version) {
            throw const ApiFailure(FailureKind.conflict, '任务已有新版本，请重新读取后再申请修改');
          }
          final candidate = _taskDraft(
            Command('create', {
              ...current.fields,
              'title': current.title,
              if (command.action == 'transfer')
                'participantIds': transferParticipants ?? [v['ownerId']],
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
        if (command.action == 'request-delete') {
          final reason = '${v['删除理由'] ?? v['reason'] ?? ''}'.trim();
          if (reason.isEmpty || command.version == null) {
            throw const ApiFailure(FailureKind.validation, '请填写删除理由并读取当前版本');
          }
          return await _postRecord('/tasks/$id/deletions', {
            'version': command.version,
            'reason': reason,
          });
        }
        final event = switch (command.action) {
          'receive' => 'RECEIVED',
          'feedback' => 'FEEDBACK',
          'return' => 'RETURNED',
          'accept' => 'ACCEPTED',
          'withdraw' => 'WITHDRAWN',
          'archive' => 'ARCHIVED',
          _ => throw const ApiFailure(FailureKind.unavailable, '后端未提供该任务操作'),
        };
        if (command.version == null) {
          throw const ApiFailure(FailureKind.validation, '请重新读取任务当前版本');
        }
        return await _postRecord('/tasks/$id/events', {
          'type': event,
          'version': command.version,
          if (command.action == 'feedback') 'attachments': v['attachments'] ?? [],
          if (v['成果说明'] != null)
            'text':
                '${v['成果说明']}${'${v['遇到的阻碍'] ?? ''}'.trim().isEmpty ? '' : '\n\n遇到的阻碍：${v['遇到的阻碍']}'}',
          if (v['验收意见'] != null) 'text': v['验收意见'],
          if (v['撤回原因'] != null) 'text': v['撤回原因'],
        });
      }
      if (resource == 'tasks/comments') {
        if (command.idempotencyKey == null || command.idempotencyKey!.trim().isEmpty) {
          throw const ApiFailure(FailureKind.validation, '评论需要幂等键', code: 'IDEMPOTENCY_REQUIRED');
        }
        final text = '${v['text'] ?? v['评语'] ?? ''}'.trim();
        if (text.isEmpty) {
          throw const ApiFailure(FailureKind.validation, '评论不能为空');
        }
        return await _postRecord(
          '/tasks/${Uri.encodeComponent(_commandId(command))}/comments',
          {
            'text': text,
            if (v['parentCommentId'] != null || v['parentId'] != null)
              'parentId': v['parentCommentId'] ?? v['parentId'],
          },
          idempotencyKey: command.idempotencyKey,
        );
      }
      if (resource == 'task-labels') {
        if (command.action == 'create') {
          return await _postRecord('/task-labels', _taskLabelDraft(command));
        }
        if (command.action == 'update') {
          return await _putRecord(
            '/task-labels/${Uri.encodeComponent(_commandId(command))}',
            _taskLabelDraft(command),
          );
        }
        throw const ApiFailure(FailureKind.unavailable, '后端未提供该标签操作');
      }
      if (resource == 'logs') {
        if (!const {'update-content', 'update', 'submit', 'save-draft'}.contains(command.action)) {
          throw const ApiFailure(FailureKind.unavailable, '不支持该日志操作，请使用当前日志编辑入口');
        }
        if (command.action == 'update-content' || command.action == 'update') {
          final work = '${v['work'] ?? v['今日工作'] ?? ''}'.trim();
          if (work.isEmpty || command.version == null) {
            throw const ApiFailure(
              FailureKind.validation,
              '请填写今日工作并读取当前日志版本',
            );
          }
          final response = await dio.put<Map<String, dynamic>>(
            '/logs/${Uri.encodeComponent(_commandId(command))}/content',
            data: {'work': v['work'] ?? v['今日工作'], 'version': command.version},
            options: Options(
              headers: {'Idempotency-Key': ?command.idempotencyKey},
            ),
          );
          return _record(response.data!);
        }
        if (command.action == 'submit') {
          var id = v['id']?.toString();
          var submitVersion = command.version;
          if (id != null && id.isNotEmpty && submitVersion == null) {
            throw const ApiFailure(FailureKind.validation, '请读取日志当前版本后提交');
          }
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
        if (command.action == 'reroute') {
          return await _postRecord(
            '/reviews/${Uri.encodeComponent(_commandId(command))}/reroute',
            const <String, dynamic>{},
          );
        }
        if (!['approve', 'reject'].contains(command.action)) {
          throw const ApiFailure(FailureKind.validation, '不支持的审核操作');
        }
        return await _postRecord(
          '/reviews/${Uri.encodeComponent(_commandId(command))}/decision',
          {
            'approve': command.action == 'approve',
            'reason': v['reason'] ?? v['驳回原因'] ?? '',
            'expectedVersion': v['expectedVersion'] ?? command.version,
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
          if (v.containsKey('个人介绍')) 'introduction': v['个人介绍'],
          if (v.containsKey('手机号'))
            'phone': v['手机号'] == null || '${v['手机号']}'.trim().isEmpty ? null : v['手机号'],
          if (v.containsKey('邮箱'))
            'email': v['邮箱'] == null || '${v['邮箱']}'.trim().isEmpty ? null : v['邮箱'],
          if (v.containsKey('性别'))
            'gender': v['性别'] == null || '${v['性别']}'.trim().isEmpty ? null : v['性别'],
          if (v.containsKey('年龄')) 'age': v['年龄'],
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
          throw const ApiFailure(
            FailureKind.unavailable,
            '审核方式由组织直属关系确定，移动端不再配置多级审核开关',
          );
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
          queryParameters: {
            'date': date,
            'period': period,
            'resource': target,
            for (final key in ['departmentId', 'teamId', 'ownerId', 'groupBy'])
              if (v[key] != null && '${v[key]}'.isNotEmpty) key: v[key],
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

  Future<Record> _putRecord(String path, Map<String, dynamic> body) async {
    final response = await dio.put<Map<String, dynamic>>(path, data: body);
    return _record(response.data!);
  }
}
