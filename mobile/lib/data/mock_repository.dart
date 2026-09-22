import '../core/failure.dart';
import 'models.dart';
import 'repository.dart';

enum DemoScenario { normal, empty, offline, forbidden }

class DemoStore {
  final Map<String, List<Record>> records = {};
  final Map<String, Record> responses = {};
}

class MockRepository implements Repository {
  MockRepository(
    this.session, {
    this.scenario = DemoScenario.normal,
    DemoStore? store,
  }) : store = store ?? DemoStore();
  final Session session;
  final DemoScenario scenario;
  final DemoStore store;
  String _resource(String r) => r == 'logs/subordinates' ? 'logs' : r;
  Future<void> _check(String resource) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (scenario == DemoScenario.offline) {
      throw const ApiFailure(FailureKind.timeout, '演示：网络连接超时，请重试');
    }
    if (!session.active || scenario == DemoScenario.forbidden) {
      throw const ApiFailure(FailureKind.forbidden, '当前账号无权访问');
    }
    if ((resource.startsWith('organization/admin') || resource == 'audit') &&
        !session.administrator) {
      throw const ApiFailure(FailureKind.forbidden, '此功能仅向管理员开放');
    }
    if (['logs/subordinates', 'analytics', 'organization'].contains(resource) &&
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
    final now = DateTime.now();
    if (resource == 'organization') {
      return [
        for (final (i, name) in ['林小满', '陈一诺', '许知远'].indexed)
          Record(
            id: 'u${i + 1}',
            title: name,
            subtitle: i == 2 ? '技术部 · 研发团队' : '产品部 · 体验团队',
            fields: {
              'body': ['关注团队协作与产品体验。', '用清晰的设计解决真实问题。', '让每一个功能稳定交付。'][i],
              'role': i == 0 ? '团队长' : '员工',
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
          fields: {'姓名': session.name, '个人介绍': '认真工作，也记得好好生活。', '头像': ''},
        ),
      ];
    }
    if (resource == 'feedback') return [];
    final titles = switch (resource) {
      'dashboard/company' => ['秋季产品体验升级计划', '本周五产品评审', '跨部门协作约定'],
      'dashboard/personal' => ['梳理工作台体验', '准备周会分享', '整理接口联调清单', '确认评审时间', '补充设计规范', '检查版本质量', '总结客户反馈', '完善交互细节', '更新测试清单'],
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
      'reviews' => ['日报内容修订', '公司展示项更新'],
      'notifications' => [
        '你有一项新的任务',
        '日报修订等待复核',
        '今日工作日志待阅',
        '任务即将截止',
        '公司展示项审核通过',
      ],
      'audit' => ['日报候选版本提交', '任务派发记录', '员工归属确认'],
      'ai-maps' => ['确认交互稿中的关键依赖', '整理客户访谈结论', '为本周评审预留时间'],
      'organization/admin' => ['产品部', '市场部', '技术部'],
      _ => <String>[],
    };
    return [
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
            'deadline': now.add(Duration(days: i - 1)).toIso8601String(),
            'createdAt': now
                .subtract(Duration(days: i))
                .toUtc()
                .toIso8601String(),
            'businessDate': stamp(now.subtract(Duration(days: i))),
            'status': resource == 'tasks'
                ? ['待接收', '进行中', '待验收', '需补充', '已验收', '已归档'][i % 6]
                : '已提交',
            '紧急程度': i % 3 == 0 ? '紧急' : '普通',
            '所属分组': '产品体验',
            '主负责人': ['林小满', '陈一诺', '许知远'][i % 3],
            '协作人': '许知远',
            '附件': i % 2 == 0 ? '交互说明.pdf' : '',
            'dispatcherId': 'u1',
            'acceptedAt': i >= 4
                ? now.add(Duration(days: i - 2)).toIso8601String()
                : null,
            '成果说明': '已完成初稿，请查看附件并安排验收。',
            'events': [
              '${stamp(now.subtract(Duration(days: i)))} · 林小满创建任务',
              if (i > 0) '负责人已接收任务',
            ],
            'type': ['任务', '审批', '日志', '截止提醒', '审核结果'][i % 5],
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
            'comments': <String>[],
            'sources': ['/item/logs/1', '/item/tasks/1'],
          },
        ),
    ];
  }

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
    if (resource == 'tasks' && !session.manager) {
      items = items.where((r) => r.ownerId == session.id);
    }
    if (resource == 'reviews' && !session.manager) {
      items = items.where((r) => r.ownerId == session.id);
    }
    if (resource == 'notifications') {
      items = items.where((r) => r.ownerId == session.id);
    }
    if (query.from != null && query.to != null) {
      items = items.where((r) {
        final raw = resource.startsWith('logs')
            ? '${r.fields['businessDate']}T00:00:00+08:00'
            : '${r.fields['deadline'] ?? r.fields['createdAt']}';
        final date = DateTime.tryParse(raw);
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
  Future<Record> detail(String resource, String id) async {
    await _check(resource);
    if (resource == 'organization/profile' &&
        !rows(resource).any((r) => r.id == id)) {
      rows(resource).add(
        Record(
          id: id,
          title: session.name,
          ownerId: id,
          fields: {'姓名': session.name, '个人介绍': '认真工作，也记得好好生活。'},
        ),
      );
    }
    final item = rows(resource).where((r) => r.id == id).firstOrNull;
    if (item == null) throw const ApiFailure(FailureKind.notFound, '记录不存在或已归档');
    if (['logs', 'logs/subordinates', 'tasks', 'reviews'].contains(resource) &&
        !session.manager &&
        item.ownerId != session.id) {
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
        session.manager &&
        item.ownerId != session.id) {
      final entries = rows('logs'),
          index = entries.indexWhere((r) => r.id == id);
      entries[index] = Record(
        id: item.id,
        title: item.title,
        subtitle: item.subtitle,
        ownerId: item.ownerId,
        version: item.version,
        fields: {
          ...item.fields,
          'readBy':
              '${session.name} · ${DateTime.now().toString().substring(0, 16)}',
        },
      );
      return entries[index];
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
          previous.ownerId != session.id) {
        throw const ApiFailure(FailureKind.forbidden, '请切换为主负责人操作');
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
    if (resource == 'logs/comments') {
      final logs = rows('logs');
      final pos = logs.indexWhere((r) => r.id == id);
      if (pos >= 0) {
        logs[pos] = copy(logs[pos], {
          'comments': [
            ...?logs[pos].fields['comments'] as List?,
            '${session.name}：${v['评语']}',
          ],
        });
      }
      return const Record(id: 'comment', title: '评语已保存');
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
      fields['status'] = '已提交';
      fields['versions'] = [
        ...?previous?.fields['versions'] as List?,
        {
          'version': (previous?.version ?? 0) + 1,
          'body': fields['今日工作'],
          'time': DateTime.now().toString().substring(0, 16),
        },
      ];
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
