import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:dio/dio.dart';
import 'package:pandora_mobile/data/models/attachments.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/log_edit_window.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

enum DemoScenario { normal, empty, offline, forbidden }

class DemoStore {
  final Map<String, List<Record>> records = {};
  final Map<String, Record> responses = {};
  final Map<String, SelectedAttachment> attachments = {};
}

class MockRepository implements Repository {
  MockRepository(
    this.session, {
    this.scenario = DemoScenario.normal,
    DemoStore? store,
    DateTime Function()? clock,
  }) : store = store ?? DemoStore(),
       clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  final Session session;
  final DemoScenario scenario;
  final DemoStore store;
  String _resource(String r) => switch (r) {
    'logs/subordinates' => 'logs',
    'organization/dispatch-people' => 'organization',
    _ => r,
  };
  @override
  Future<UploadedAttachment> uploadAttachment(
    SelectedAttachment file, {
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    file.validate();
    await _check('attachments');
    if (cancelToken?.isCancelled == true) {
      throw const ApiFailure(FailureKind.unavailable, '上传已取消');
    }
    final id = 'demo-file-${DateTime.now().microsecondsSinceEpoch}';
    store.attachments[id] = file;
    onProgress?.call(file.bytes.length, file.bytes.length);
    return UploadedAttachment(
      id: id,
      name: safeAttachmentName(file.name),
      size: file.bytes.length,
    );
  }

  @override
  Future<DownloadedAttachment> downloadAttachment(
    String id, {
    CancelToken? cancelToken,
  }) async {
    await _check('attachments');
    final file = store.attachments[id];
    if (file == null) {
      throw const ApiFailure(FailureKind.notFound, '演示附件没有文件内容');
    }
    return DownloadedAttachment(
      name: safeAttachmentName(file.name),
      bytes: file.bytes,
    );
  }

  Future<void> _check(String resource) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (scenario == DemoScenario.offline) {
      throw const ApiFailure(FailureKind.timeout, '演示：网络连接超时，请重试');
    }
    if (!session.canReadBusiness || scenario == DemoScenario.forbidden) {
      throw const ApiFailure(FailureKind.forbidden, '当前账号无权访问');
    }
    if ((resource.startsWith('organization/admin') || resource == 'audit') &&
        !session.administrator) {
      throw const ApiFailure(FailureKind.forbidden, '此功能仅向管理员开放');
    }
    if (['logs/subordinates', 'analytics'].contains(resource) &&
        !session.manager) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看管理范围外的数据');
    }
  }

  List<Record> rows(String resource) => store.records.putIfAbsent(
    _resource(resource),
    () => _seed(_resource(resource)),
  );
  String stamp(DateTime d) => d.toIso8601String().split('T').first;
  List<Record> _seed(String resource) {
    final instant = clock();
    final now = shanghaiWallTime(instant);
    if (resource == 'organization') {
      return [
        for (final (i, name) in ['林小满', '陈一诺', '许知远'].indexed)
          Record(
            id: 'u${i + 1}',
            title: name,
            subtitle: i == 2 ? '技术部 · 研发团队' : '产品部 · 体验团队',
            fields: {
              'body': ['关注团队协作与产品体验。', '用清晰的设计解决真实问题。', '让每一个功能稳定交付。'][i],
              'role': i == 0 ? 'LEADER' : 'EMPLOYEE',
              'status': 'ACTIVE',
              'dispatch_enabled': i == 0,
              'company_reviewer': false,
              'department_id': i == 2 ? 'd-tech' : 'd-product',
              'departmentName': i == 2 ? '技术部' : '产品部',
              'team_id': i == 2 ? 't-dev' : 't-experience',
              'managerId': i == 0 ? 'u-boss' : 'u1',
              'participatingTaskCount': [7, 5, 4][i],
              'todayLogStatus': i == 2 ? '今日日志待提交' : '今日日志已提交',
              'taskStatus': i == 1 ? '有任务待验收' : '任务推进中',
            },
          ),
      ];
    }
    if (resource == 'organization/profile') {
      return [
        Record(
          id: session.id,
          title: session.name,
          ownerId: session.id,
          fields: {
            '姓名': session.name,
            '个人介绍': '认真工作，也记得好好生活。',
            '头像': '',
            'role': session.role.name.toUpperCase(),
            'status': 'ACTIVE',
            'dispatch_enabled': session.dispatch,
            'company_reviewer': false,
            'department_id': 'd-product',
            'team_id': 't-experience',
          },
        ),
      ];
    }
    if (resource == 'feedback') return [];
    final titles = switch (resource) {
      'dashboard/company' => ['秋季产品体验升级计划', '本周五产品评审', '跨部门协作约定'],
      'dashboard/personal' => [
        '梳理工作台体验',
        '准备周会分享',
        '整理接口联调清单',
        '确认评审时间',
        '补充设计规范',
        '检查版本质量',
        '总结客户反馈',
        '完善交互细节',
        '更新测试清单',
      ],
      'tasks' => [
        '完成工作台交互稿',
        '整理客户访谈记录',
        '确认本周开发安排',
        '补充验收清单',
        '优化首页加载体验',
        '完成上周设计归档',
      ],
      'logs' => [
        '梳理工作台交互流程',
        '完成客户访谈与结论整理',
        '推进接口联调',
        '补充需求评审记录',
        '完成设计走查',
        '整理版本发布清单',
        '完成周会纪要',
        '跟进需求反馈',
        '确认验收标准',
      ],
      'reviews' => ['任务内容调整', '公司展示项更新'],
      'notifications' => [
        '你有一项新的任务',
        '任务修改等待复核',
        '有人评论了你的日志',
        '任务即将截止',
        '公司展示项审核通过',
      ],
      'audit' => ['日报候选版本提交', '任务派发记录', '员工归属确认'],
      'ai-maps' => ['确认交互稿中的关键依赖', '整理客户访谈结论', '为本周评审预留时间'],
      'organization/admin' => ['产品部', '市场部', '技术部'],
      _ => <String>[],
    };
    final result = [
      for (final (i, title) in titles.indexed)
        Record(
          id: '${i + 1}',
          title: title,
          ownerId: resource == 'reviews'
              ? (i == 0 ? 'u2' : 'u1')
              : 'u${i % 3 + 1}',
          subtitle: resource == 'logs'
              ? '${stamp(now.subtract(Duration(days: i)))} · ${['林小满', '陈一诺', '许知远'][i % 3]}'
              : '产品体验 · ${stamp(now.subtract(Duration(days: i)))}',
          fields: {
            'body': [
              '梳理首页信息层级，明确四大板块与常用入口。',
              '整理访谈结论，优先解决任务反馈不及时的问题。',
              '协调设计与研发，明确本周交付边界。',
            ][i % 3],
            '今日工作': title,
            '明日计划': '核对关键依赖，与协作成员确认交付安排。',
            '遇到的阻碍': i % 2 == 0 ? '等待业务方确认评审时间' : '暂无阻碍',
            '工时': '${6 + i % 3}',
            '关联任务': '${i % 3 + 1}',
            'startAt': DateTime(
              now.year,
              now.month,
              now.day + (resource == 'tasks' ? i - 1 : -i),
              9 + i % 3 * 2,
            ).toIso8601String(),
            'endAt': DateTime(
              now.year,
              now.month,
              now.day + (resource == 'tasks' ? i - 1 : -i),
              11 + i % 3 * 2,
            ).toIso8601String(),
            'deadline': DateTime(
              now.year,
              now.month,
              now.day + i - 1,
              18,
            ).toIso8601String(),
            'createdAt': instant
                .subtract(Duration(days: i))
                .toUtc()
                .toIso8601String(),
            'businessDate': stamp(now.subtract(Duration(days: i))),
            if (resource == 'logs')
              'submittedAt': instant
                  .subtract(Duration(days: i, hours: 2))
                  .toUtc()
                  .toIso8601String(),
            if (resource == 'logs') 'authorName': ['林小满', '陈一诺', '许知远'][i % 3],
            'status': resource == 'tasks'
                ? ['待接收', '进行中', '待验收', '需补充', '已验收', '已归档'][i % 6]
                : '已提交',
            '所属分组': '产品体验',
            'participantIds': ['u${i % 3 + 1}', 'u${(i + 1) % 3 + 1}'],
            'participantNames': [
              ['林小满', '陈一诺', '许知远'][i % 3],
              ['林小满', '陈一诺', '许知远'][(i + 1) % 3],
            ],
            'tagId': [
              'company-important',
              'department-design',
              'personal-today',
            ][i % 3],
            'tagName': ['重要', '设计', '今日'][i % 3],
            'tagCategory': ['公司', '部门', '个人'][i % 3],
            'tagColor': ['#FFB35C', '#9EDCC3', '#B9DDF5'][i % 3],
            '附件': i % 2 == 0 ? '交互说明.pdf' : '',
            'dispatcherId': resource == 'tasks'
                ? (i.isEven ? 'u2' : 'u1')
                : 'u1',
            'acceptedAt': i >= 4
                ? now.add(Duration(days: i - 2)).toIso8601String()
                : null,
            '成果说明': '已完成初稿，请查看附件并安排验收。',
            'events': [
              '${stamp(now.subtract(Duration(days: i)))} · 林小满创建任务',
              if (i > 0) '负责人已接收任务',
            ],
            'type': ['任务', '审批', '评论', '截止提醒', '审核结果'][i % 5],
            'targetResource': [
              'tasks',
              'reviews',
              'logs',
              'tasks',
              'reviews',
            ][i % 5],
            'targetId': ['1', '1', '1', '2', '2'][i % 5],
            'read': false,
            'reviewState': i == 0 ? '待审' : '已通过',
            'step': 0,
            'before': '完成初步调研',
            'after': '完成调研并补充三份访谈记录',
            'reason': '补充最新工作成果，便于团队同步。',
            'reviewEvents': <String>[],
            'comments': <Map<String, dynamic>>[],
            'sources': ['/item/logs/1', '/item/tasks/1'],
          },
        ),
    ];
    // Stable distinct records show busy days without duplicating one daily log.
    if (resource == 'tasks' || resource == 'logs') {
      final monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      if (resource == 'tasks') {
        result.add(
          Record(
            id: 'demo-training-span',
            title: '数据结构实训',
            ownerId: session.id,
            fields: {
              'startAt': monday
                  .add(const Duration(days: 3, hours: 9))
                  .toIso8601String(),
              'deadline': monday
                  .add(const Duration(days: 8, hours: 18))
                  .toIso8601String(),
              'participantIds': [session.id],
              'participantNames': [session.name],
              'dispatcherId': 'u-boss',
              'status': '进行中',
              'tagName': '实训',
              'tagColor': '#BE8A68',
            },
          ),
        );
      }
      for (var day = 0; day < 7; day++) {
        final date = monday.add(Duration(days: day));
        final count = resource == 'tasks' ? 10 : 3;
        for (var i = 0; i < count; i++) {
          final owner = 'u${i % 3 + 1}';
          if (resource == 'logs' &&
              result.any(
                (r) =>
                    r.ownerId == owner &&
                    r.fields['businessDate'] == stamp(date),
              )) {
            continue;
          }
          if (resource == 'logs' &&
              date.isAfter(DateTime(now.year, now.month, now.day))) {
            continue;
          }
          result.add(
            Record(
              id: 'demo-$resource-$day-$i',
              title:
                  '${['核对需求与交付', '整理评审意见', '完善交互方案', '验证任务链路', '同步项目进展'][i % 5]} · ${day + 1}-${i + 1}',
              ownerId: owner,
              fields: {
                'businessDate': stamp(date),
                'startAt': DateTime(
                  date.year,
                  date.month,
                  date.day,
                  9 + i % 7,
                ).toIso8601String(),
                'endAt': DateTime(
                  date.year,
                  date.month,
                  date.day,
                  10 + i % 7,
                ).toIso8601String(),
                'deadline': DateTime(
                  date.year,
                  date.month,
                  date.day,
                  18,
                ).toIso8601String(),
                'status': resource == 'tasks' ? '进行中' : '已提交',
                'submittedAt': stamp(date) == stamp(now)
                    ? instant
                          .subtract(const Duration(hours: 2))
                          .toUtc()
                          .toIso8601String()
                    : '${stamp(date)}T18:00:00+08:00',
                'authorName': ['林小满', '陈一诺', '许知远'][i % 3],
                'participantIds': [owner],
                'participantNames': [
                  ['林小满', '陈一诺', '许知远'][i % 3],
                ],
                'dispatcherId': i.isEven ? 'u-boss' : 'u1',
                'tagId': [
                  'company-important',
                  'department-design',
                  'personal-today',
                ][i % 3],
                'tagName': ['重要', '设计', '今日'][i % 3],
                'tagColor': ['#FFB35C', '#9EDCC3', '#B9DDF5'][i % 3],
                '今日工作': '完成需求核对及协作沟通',
                'body': '完成需求核对及协作沟通',
                '明日计划': '跟进交付并整理验收结果',
                '遇到的阻碍': '暂无',
                '工时': '6',
                'comments': <Map<String, dynamic>>[],
              },
            ),
          );
        }
      }
    }
    return result;
  }

  Set<String> get visiblePeople {
    final ids = <String>{session.id};
    if (!session.manager) return ids;
    final people = rows('organization');
    if (session.administrator || session.role == UserRole.founder) {
      return {...ids, ...people.map((p) => p.id)};
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final person in people) {
        if (ids.contains('${person.fields['managerId']}') &&
            ids.add(person.id)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  bool taskVisible(Record r) =>
      visiblePeople.contains(r.ownerId) ||
      visiblePeople.contains('${r.fields['dispatcherId']}') ||
      (r.fields['participantIds'] as List? ?? const []).any(
        (id) => visiblePeople.contains('$id'),
      );

  @override
  Future<PageResult> list(String resource, Query query) async {
    await _check(resource);
    if (scenario == DemoScenario.empty) return const PageResult([]);
    if (query.ownerId != null &&
        query.ownerId != session.id &&
        !session.manager) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看他人数据');
    }
    var items = rows(
      resource,
    ).where((r) => '${r.title}${r.subtitle}'.contains(query.search));
    if (resource == 'organization') {
      items = items.where((r) => visiblePeople.contains(r.id));
    }
    if (resource == 'tasks') items = items.where(taskVisible);
    if (resource == 'logs/subordinates') {
      items = items.where(
        (r) =>
            r.ownerId != session.id &&
            visiblePeople.contains(r.ownerId) &&
            isSubmittedDiary(r),
      );
    }
    if ([
      'logs',
      'dashboard/personal',
      'private-notes',
      'feedback',
    ].contains(resource)) {
      items = items.where((r) => r.ownerId == (query.ownerId ?? session.id));
    }
    if (resource == 'logs/subordinates' && query.ownerId != null) {
      items = items.where((r) => r.ownerId == query.ownerId);
    }
    if (resource == 'organization/dispatch-people') {
      if (!session.manager || !session.dispatch) {
        throw const ApiFailure(FailureKind.forbidden, '没有派发资格');
      }
      items = items.where((p) => p.fields['status'] == 'ACTIVE');
    }
    if (resource == 'tasks' && !session.manager) {
      items = items.where((r) {
        final participants = (r.fields['participantIds'] as List?)
            ?.map((id) => '$id')
            .toSet();
        return r.ownerId == session.id ||
            participants?.contains(session.id) == true ||
            '${r.fields['dispatcherId'] ?? ''}' == session.id;
      });
    }
    if (resource == 'reviews' && !session.manager) {
      items = items.where((r) => r.ownerId == session.id);
    }
    if (resource == 'notifications') {
      items = items.where((r) => r.ownerId == session.id);
    }
    if (query.from != null && query.to != null) {
      items = items.where((r) {
        DateTime? parseBusinessInstant(dynamic value) {
          final raw = '$value';
          return DateTime.tryParse(
            RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(raw) ? raw : '$raw+08:00',
          );
        }

        if (resource == 'tasks') {
          final deadline = parseBusinessInstant(
            r.fields['deadline'] ?? r.fields['createdAt'],
          );
          final start = parseBusinessInstant(
            r.fields['startAt'] ??
                r.fields['deadline'] ??
                r.fields['createdAt'],
          );
          return start != null &&
              deadline != null &&
              start.isBefore(query.to!) &&
              !deadline.isBefore(query.from!);
        }
        final raw = resource.startsWith('logs')
            ? '${r.fields['businessDate']}T00:00:00+08:00'
            : '${r.fields['deadline'] ?? r.fields['createdAt']}';
        final date = parseBusinessInstant(raw);
        return date != null &&
            !date.isBefore(query.from!) &&
            date.isBefore(query.to!);
      });
    }
    final result = items.toList();
    if (resource == 'dashboard/personal') {
      result.sort(
        (a, b) => (int.tryParse('${a.fields['排序位置']}') ?? 0).compareTo(
          int.tryParse('${b.fields['排序位置']}') ?? 0,
        ),
      );
    }
    return PageResult(result, total: result.length);
  }

  @override
  Future<Record> detail(String resource, String id, {String? ownerId}) async {
    await _check(resource);
    if (resource == 'organization/tree') {
      return Record(
        id: 'tree',
        title: '演示组织',
        fields: {
          'departments': [
            {'id': 'd-product', 'name': '产品部', 'version': 1},
            {'id': 'd-tech', 'name': '技术部', 'version': 1},
          ],
          'teams': [
            {
              'id': 't-experience',
              'name': '体验团队',
              'department_id': 'd-product',
              'version': 1,
            },
            {
              'id': 't-dev',
              'name': '研发团队',
              'department_id': 'd-tech',
              'version': 1,
            },
          ],
          'people': [
            for (final person in rows('organization'))
              Record(
                id: person.id,
                title: person.title,
                subtitle: person.subtitle,
                ownerId: person.ownerId,
                version: person.version,
                fields: {
                  ...person.fields,
                  'department_id': person.id == 'u3' ? 'd-tech' : 'd-product',
                  'team_id': person.id == 'u3' ? 't-dev' : 't-experience',
                },
              ),
          ],
        },
      );
    }
    if (resource == 'organization/policy') {
      if (!session.administrator) {
        throw const ApiFailure(FailureKind.forbidden, '仅管理员可配置');
      }
      return const Record(
        id: 'policy',
        title: '当前审核策略',
        fields: {
          'review_policy': {
            'taskTeamReview': true,
            'taskDepartmentReview': true,
          },
        },
      );
    }
    if (resource == 'organization/profile' &&
        !rows(resource).any((r) => r.id == id)) {
      final person = rows('organization').where((r) => r.id == id).firstOrNull;
      if (person == null) throw const ApiFailure(FailureKind.notFound, '成员不存在');
      rows(resource).add(
        Record(
          id: id,
          title: person.title,
          ownerId: id,
          fields: {
            ...person.fields,
            '姓名': person.title,
            '个人介绍': person.fields['body'],
          },
        ),
      );
    }
    final item = rows(resource).where((r) => r.id == id).firstOrNull;
    if (item == null) throw const ApiFailure(FailureKind.notFound, '记录不存在或已归档');
    if (resource == 'tasks' && !taskVisible(item) ||
        resource == 'organization' && !visiblePeople.contains(item.id)) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看管理范围外的数据');
    }
    if (['logs', 'logs/subordinates', 'tasks', 'reviews'].contains(resource) &&
        !session.manager &&
        item.ownerId != session.id &&
        !(resource == 'tasks' && taskVisible(item))) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看其他成员的记录');
    }
    if ([
          'dashboard/personal',
          'private-notes',
          'feedback',
        ].contains(resource) &&
        item.ownerId != session.id &&
        !(resource == 'dashboard/personal' && session.manager)) {
      throw const ApiFailure(FailureKind.forbidden, '仅本人可见');
    }
    if (resource.startsWith('logs') &&
        item.ownerId != session.id &&
        !isSubmittedDiary(item)) {
      throw const ApiFailure(FailureKind.forbidden, '草稿仅本人可见');
    }
    if (resource == 'logs' || resource == 'logs/subordinates') {
      if (!visiblePeople.contains(item.ownerId)) {
        throw const ApiFailure(FailureKind.forbidden, '无权查看该日志');
      }
      return Record(
        id: item.id,
        title: item.title,
        subtitle: item.subtitle,
        ownerId: item.ownerId,
        version: item.version,
        fields: {
          ...item.fields,
          'canEdit':
              item.ownerId == session.id &&
              LogEditWindow(item).canEditAt(clock()),
          'editableUntil': LogEditWindow(item).until?.toUtc().toIso8601String(),
          'serverNow': clock().toUtc().toIso8601String(),
        },
      );
    }
    return item;
  }

  Record copy(
    Record r,
    Map<String, dynamic> fields, {
    String? ownerId,
    String? title,
  }) => Record(
    id: r.id,
    title: title ?? r.title,
    subtitle: r.subtitle,
    ownerId: ownerId ?? r.ownerId,
    version: r.version + 1,
    fields: {...r.fields, ...fields},
  );
  void notify(
    String title,
    String resource,
    String id,
    String owner,
    String type,
  ) {
    rows('notifications').insert(
      0,
      Record(
        id: 'n${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        subtitle: '刚刚 · 工作提醒',
        ownerId: owner,
        fields: {
          'type': type,
          'targetResource': resource,
          'targetId': id,
          'read': false,
        },
      ),
    );
  }

  @override
  Future<Record> execute(String resource, Command command) async {
    if (resource != 'auth') await _check(resource);
    final v = command.values, action = command.action;
    final key = command.idempotencyKey;
    if (key != null && store.responses.containsKey(key)) {
      return store.responses[key]!;
    }
    if (resource == 'auth') {
      if (v.containsKey('role')) {
        throw const ApiFailure(FailureKind.forbidden, '注册只能申请员工账号');
      }
      return const Record(id: 'auth', title: '演示登录');
    }
    if (resource == 'tasks' &&
        action == 'create' &&
        (!session.manager || !session.dispatch)) {
      throw const ApiFailure(FailureKind.forbidden, '当前账号没有任务派发资格');
    }
    if (resource == 'organization/admin') {
      if (!session.administrator) {
        throw const ApiFailure(FailureKind.forbidden, '仅管理员可配置');
      }
      if ('${v['reason'] ?? ''}'.trim().isEmpty || command.version == null) {
        throw const ApiFailure(FailureKind.validation, '请读取当前版本并填写理由');
      }
      final request = Record(
        id: 'org${DateTime.now().microsecondsSinceEpoch}',
        title: '组织配置修改申请',
        ownerId: session.id,
        fields: {
          'reviewState': '待审',
          'targetResource': 'organization/admin',
          'targetId': v['id'],
          'candidate': {...v},
          'reason': v['reason'],
          'baseVersion': command.version,
          'before': '当前配置继续生效',
          'after': {...v},
          'reviewEvents': <String>[],
        },
      );
      rows('reviews').insert(0, request);
      return request;
    }
    if (resource == 'dashboard/company' && !session.manager) {
      throw const ApiFailure(FailureKind.forbidden, '没有公司发布权限');
    }
    if (resource == 'auth' && v.containsKey('role')) {
      throw const ApiFailure(FailureKind.forbidden, '注册只能申请员工账号');
    }
    if (resource == 'ai') {
      final date = DateTime.tryParse('${v['date']}') ?? DateTime.now();
      final range = BusinessRange(date, '${v['period'] ?? '日'}');
      final logs = await list('logs', Query(from: range.from, to: range.to));
      final tasks = await list('tasks', Query(from: range.from, to: range.to));
      final input = [...tasks.items, ...logs.items];
      store.records['ai-maps'] = [
        for (final (i, r) in input.take(3).indexed)
          Record(
            id: '${i + 1}',
            title: '推进：${r.title}',
            ownerId: session.id,
            fields: {
              'body':
                  '结合所选${v['period'] ?? '日'}范围，优先确认「${r.title}」的交付内容、依赖和负责人。',
              'createdAt': DateTime.now().toIso8601String(),
              'sourceResource': tasks.items.contains(r) ? 'tasks' : 'logs',
              'sourceId': r.id,
            },
          ),
      ];
      if (input.isEmpty) {
        return const Record(id: 'empty', title: '所选日期暂无工作记录');
      }
      return rows('ai-maps').first;
    }
    if (resource == 'tasks/comments' || resource == 'logs/comments') {
      final targetResource = resource.split('/').first;
      final target = await detail(targetResource, '${v['id'] ?? ''}');
      if (targetResource == 'logs' && !isSubmittedDiary(target)) {
        throw const ApiFailure(FailureKind.validation, '请先提交日志再评论');
      }
      final text = '${v['text'] ?? v['评语'] ?? ''}'.trim();
      if (text.isEmpty) {
        throw const ApiFailure(FailureKind.validation, '评论不能为空');
      }
      if (action != 'comment' && action != 'create') {
        throw const ApiFailure(FailureKind.validation, '评论发布后不能编辑或删除');
      }
      final comments = List<dynamic>.from(
        target.fields['comments'] as List? ?? const [],
      );
      final parent = v['parentCommentId'];
      if (parent != null &&
          !comments.any((c) => c is Map && c['id'] == parent)) {
        throw const ApiFailure(FailureKind.validation, '回复的评论不存在');
      }
      final comment = {
        'id': 'c${clock().microsecondsSinceEpoch}-${comments.length}',
        'text': text,
        'actorId': session.id,
        'actorName': session.name,
        'createdAt': clock().toUtc().toIso8601String(),
        'parentCommentId': ?parent,
      };
      comments.add(comment);
      final targets = rows(targetResource);
      final pos = targets.indexWhere((r) => r.id == target.id);
      targets[pos] = Record(
        id: target.id,
        title: target.title,
        ownerId: target.ownerId,
        subtitle: target.subtitle,
        version: target.version,
        fields: {...targets[pos].fields, 'comments': comments},
      );
      notify(
        '${session.name} 评论了${targetResource == 'logs' ? '日志' : '任务'}',
        targetResource,
        target.id,
        target.ownerId,
        '评论',
      );
      final result = Record(
        id: '${comment['id']}',
        title: '评论已发布',
        fields: comment,
      );
      if (key != null) store.responses[key] = result;
      return result;
    }
    final records = rows(resource);
    if (resource == 'notifications' && action == 'read-all') {
      for (var i = 0; i < records.length; i++) {
        if (records[i].ownerId == session.id) {
          records[i] = copy(records[i], {'read': true});
        }
      }
      return const Record(id: 'read-all', title: '全部已读');
    }
    String? id = v['id'] as String?;
    if (resource == 'logs' && action == 'submit' && id == null) {
      id = records
          .where(
            (r) =>
                r.ownerId == session.id &&
                r.fields['businessDate'] == v['businessDate'],
          )
          .firstOrNull
          ?.id;
    }
    final index = records.indexWhere((r) => r.id == id);
    final previous = index < 0 ? null : records[index];
    if (resource == 'logs' && action == 'read') {
      final diary = await detail('logs', id ?? '');
      if (!isSubmittedDiary(diary)) {
        throw const ApiFailure(FailureKind.forbidden, '草稿不能记录已读');
      }
      records[index] = Record(
        id: diary.id,
        title: diary.title,
        subtitle: diary.subtitle,
        ownerId: diary.ownerId,
        version: diary.version,
        fields: {
          ...diary.fields,
          'readBy':
              '${session.name} · ${DateTime.now().toString().substring(0, 16)}',
        },
      );
      return Record(id: diary.id, title: '演示阅读已登记', fields: const {'ok': true});
    }
    if (resource == 'logs') {
      if (previous != null && previous.ownerId != session.id) {
        throw const ApiFailure(FailureKind.forbidden, '仅作者可修改日志');
      }
      if (previous != null &&
          isSubmittedDiary(previous) &&
          !LogEditWindow(previous).canEditAt(clock())) {
        throw const ApiFailure(FailureKind.forbidden, '日志提交已满24小时，已锁定');
      }
      if (action == 'request-review') {
        throw const ApiFailure(FailureKind.validation, '日志直接保存，不需要审批');
      }
      if (action == 'update' &&
          (previous == null || !isSubmittedDiary(previous))) {
        throw const ApiFailure(FailureKind.validation, '请先提交日志');
      }
      if (action == 'save-draft' &&
          previous != null &&
          isSubmittedDiary(previous)) {
        throw const ApiFailure(FailureKind.validation, '已提交日志请直接修改');
      }
      if (action == 'submit' &&
          previous != null &&
          isSubmittedDiary(previous)) {
        throw const ApiFailure(FailureKind.conflict, '日志已经提交，请直接修改');
      }
      if (action != 'save-draft' &&
          '${v['今日工作'] ?? previous?.fields['今日工作'] ?? ''}'.trim().isEmpty) {
        throw const ApiFailure(FailureKind.validation, '请填写今日工作');
      }
      final businessDate =
          '${v['businessDate'] ?? previous?.fields['businessDate'] ?? ''}';
      if (DateTime.tryParse(businessDate) == null) {
        throw const ApiFailure(FailureKind.validation, '请选择日志日期');
      }
      if (previous == null &&
          records.any(
            (r) =>
                r.ownerId == session.id &&
                r.fields['businessDate'] == businessDate,
          )) {
        throw const ApiFailure(FailureKind.conflict, '该日期已有日志，请打开已有记录');
      }
    }
    if (previous != null &&
        ['dashboard/personal', 'private-notes'].contains(resource) &&
        previous.ownerId != session.id) {
      throw const ApiFailure(FailureKind.forbidden, '仅本人可以修改');
    }
    if (previous != null &&
        command.version != null &&
        command.version != previous.version) {
      throw const ApiFailure(FailureKind.conflict, '版本已更新，请返回刷新后重试');
    }
    if (resource == 'reviews' &&
        (previous?.ownerId == session.id || !session.manager)) {
      throw const ApiFailure(FailureKind.forbidden, '不能审核自己的申请或无审核资格');
    }
    if (action == 'reject' && '${v['reason'] ?? ''}'.trim().isEmpty) {
      throw const ApiFailure(FailureKind.validation, '请填写驳回原因');
    }
    if (resource == 'tasks' && previous != null) {
      final state = previous.fields['status'];
      final allowed = switch (action) {
        'receive' => state == '待接收',
        'feedback' => ['进行中', '需补充'].contains(state),
        'accept' || 'return' => state == '待验收',
        'archive' => state == '已验收',
        _ => !['已归档', '已撤回'].contains(state),
      };
      if (!allowed) {
        throw const ApiFailure(FailureKind.validation, '当前任务状态不支持此操作');
      }
      if (['receive', 'feedback'].contains(action) &&
          !(previous.fields['participantIds'] as List? ?? const [])
              .map((value) => '$value')
              .contains(session.id)) {
        throw const ApiFailure(FailureKind.forbidden, '当前账号不在任务参与人范围内');
      }
      if ([
            'accept',
            'return',
            'transfer',
            'reschedule',
            'withdraw',
            'archive',
          ].contains(action) &&
          !session.manager) {
        throw const ApiFailure(FailureKind.forbidden, '需要管理者操作');
      }
    }
    if (action == 'request-review') {
      final request = Record(
        id: 'r${DateTime.now().microsecondsSinceEpoch}',
        title: '${v['title'] ?? previous?.title ?? '内容'} · 修改申请',
        ownerId: session.id,
        subtitle: '刚刚 · 等待复核',
        fields: {
          'reviewState': '待审',
          'step': 0,
          'before':
              previous?.fields['body'] ?? previous?.fields['今日工作'] ?? '尚未发布',
          'after': v['内容'] ?? v['今日工作'] ?? '',
          'reason': v['修改理由'] ?? '',
          'targetResource': resource,
          'targetId': id,
          'candidate': v,
          'reviewEvents': <String>[],
        },
      );
      rows('reviews').insert(0, request);
      notify('有新的修改申请待审核', 'reviews', request.id, 'u1', '审批');
      if (key != null) store.responses[key] = request;
      return request;
    }
    final labels = {
      'receive': '接收任务',
      'feedback': '提交成果',
      'accept': '验收通过',
      'return': '退回补充',
      'transfer': '转派任务',
      'reschedule': '调整期限',
      'withdraw': '撤回任务',
      'archive': '归档',
      'create': '创建',
      'submit': '提交日志',
      'approve': '审核通过',
      'reject': '驳回申请',
      'read': '已读',
      'update': '更新',
    };
    final fields = <String, dynamic>{
      ...?previous?.fields,
      ...v,
      'body':
          v['内容'] ??
          v['任务内容'] ??
          v['今日工作'] ??
          v['问题描述'] ??
          previous?.fields['body'] ??
          '',
      'createdAt':
          previous?.fields['createdAt'] ??
          DateTime.now().toUtc().toIso8601String(),
      'events': [
        ...?previous?.fields['events'] as List?,
        '${DateTime.now().toString().substring(0, 16)} · ${session.name} · ${labels[action] ?? '保存'}',
      ],
    };
    if (resource == 'tasks') {
      if (action == 'accept') {
        fields['acceptedAt'] = DateTime.now().toIso8601String();
      }
      fields['status'] = switch (action) {
        'receive' => '进行中',
        'feedback' => '待验收',
        'accept' => '已验收',
        'return' => '需补充',
        'withdraw' => '已撤回',
        'archive' => '已归档',
        _ => previous?.fields['status'] ?? '待接收',
      };
      fields['dispatcherId'] = previous?.fields['dispatcherId'] ?? session.id;
    }
    if (resource == 'logs') {
      fields['status'] = action == 'save-draft' ? '草稿' : '已提交';
      fields['authorName'] = session.name;
      if (action != 'save-draft') {
        fields['submittedAt'] =
            previous?.fields['submittedAt'] ??
            clock().toUtc().toIso8601String();
      }
      fields.remove('versions');
      fields.remove('canEdit');
      fields.remove('editableUntil');
    }
    if (resource == 'feedback') fields['status'] = '待处理';
    if (resource == 'notifications') fields['read'] = true;
    if (resource == 'reviews') {
      final step =
          (previous?.fields['step'] as int? ?? 0) +
          (action == 'approve' ? 1 : 0);
      fields['step'] = step;
      fields['reviewState'] = action == 'reject'
          ? '已驳回'
          : step >= 3
          ? '已通过'
          : '待审';
      fields['reviewEvents'] = [
        ...?previous?.fields['reviewEvents'] as List?,
        '${['团队复核', '部门复核', '公司复核'][(step - 1).clamp(0, 2)]} · ${session.name} · ${action == 'reject' ? '驳回：${v['reason']}' : '通过'} · ${DateTime.now().toString().substring(0, 16)}',
      ];
      if (fields['reviewState'] == '已通过' && fields['candidate'] is Map) {
        final target = rows('${fields['targetResource']}');
        final pos = target.indexWhere((r) => r.id == fields['targetId']);
        final candidate = Map<String, dynamic>.from(fields['candidate'] as Map);
        final base = pos < 0
            ? Record(
                id: 'p${DateTime.now().microsecondsSinceEpoch}',
                title: '${candidate['title']}',
                ownerId: previous!.ownerId,
              )
            : target[pos];
        final updated = copy(base, {
          ...candidate,
          'body': candidate['内容'] ?? candidate['今日工作'] ?? '',
          'status': '已提交',
          'versions': [
            ...?base.fields['versions'] as List?,
            {
              'version': base.version + 1,
              'body': candidate['今日工作'] ?? candidate['内容'],
              'time': DateTime.now().toString().substring(0, 16),
            },
          ],
        }, title: candidate['title'] as String?);
        if (pos < 0) {
          target.insert(0, updated);
        } else {
          target[pos] = updated;
        }
      }
      notify(
        '审核结果：${fields['reviewState']}',
        'reviews',
        id!,
        previous!.ownerId,
        '审核结果',
      );
    }
    final result = Record(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: v['title'] as String? ?? previous?.title ?? '演示记录',
      subtitle:
          previous?.subtitle ?? '${stamp(DateTime.now())} · ${session.name}',
      ownerId: v['ownerId'] as String? ?? previous?.ownerId ?? session.id,
      version: (previous?.version ?? 0) + 1,
      fields: fields,
    );
    if (action == 'archive' && resource == 'dashboard/personal' && index >= 0) {
      records.removeAt(index);
    } else if (index >= 0) {
      records[index] = result;
    } else {
      records.insert(0, result);
    }
    if (resource == 'tasks') {
      notify(
        '${labels[action] ?? '任务更新'}：${result.title}',
        'tasks',
        result.id,
        ['feedback'].contains(action)
            ? '${fields['dispatcherId']}'
            : result.ownerId,
        '任务',
      );
    }
    if (key != null) store.responses[key] = result;
    return result;
  }
}
