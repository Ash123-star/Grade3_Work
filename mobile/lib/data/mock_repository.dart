import '../core/failure.dart';
import 'models.dart';
import 'repository.dart';

enum DemoScenario { normal, empty, offline, forbidden }

class MockRepository implements Repository {
  MockRepository(this.session, {this.scenario = DemoScenario.normal});
  final Session session;
  final DemoScenario scenario;
  final Map<String, Record> _responses = {};
  final Map<String, List<Record>> _store = {};
  Future<void> _check(String resource) async {
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (scenario == DemoScenario.offline) {
      throw const ApiFailure(FailureKind.timeout, '演示：网络连接超时');
    }
    if (!session.active || scenario == DemoScenario.forbidden) {
      throw const ApiFailure(FailureKind.forbidden, '当前账号无权访问');
    }
    if ((resource.startsWith('organization/admin') || resource == 'audit') &&
        !session.administrator) {
      throw const ApiFailure(FailureKind.forbidden, '此功能仅向管理员开放');
    }
    if ([
          'logs/subordinates',
          'analytics',
          'organization',
          'reviews',
        ].contains(resource) &&
        !session.manager) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看管理范围外的数据');
    }
  }

  List<Record> _seed(String resource) {
    final today = DateTime.now();
    final date =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final titles = switch (resource) {
      'dashboard/company' => ['秋季产品计划', '团队协作约定', '本周重点与安排'],
      'dashboard/personal' => ['梳理工作台体验', '准备周会分享'],
      'tasks' => ['完成工作台交互稿', '整理客户访谈记录', '确认本周开发安排'],
      'logs' || 'logs/subordinates' => ['$date 工作日报', '本周工作回顾'],
      'reviews' => ['日报内容修订', '公司展示项更新'],
      'notifications' => ['你有一项新的任务', '日报修订等待复核', '今日工作日志待阅'],
      'organization' => ['林小满', '陈一诺', '许知远'],
      'organization/admin' => ['产品部', '市场部', '技术部'],
      'audit' => ['日报候选版本提交', '任务派发记录', '员工归属确认'],
      'ai-maps' => ['先确认交互稿中的阻碍', '整理今日访谈结论', '为明天的评审预留时间'],
      'analytics' => ['派发数量', '逾期数量', '按期验收率', '日报提交率', '日志待阅数', '部门工作分布'],
      _ => <String>[],
    };
    return List.generate(
      titles.length,
      (i) => Record(
        id: '${i + 1}',
        title: titles[i],
        subtitle: resource == 'organization'
            ? '产品部 · 体验团队'
            : resource == 'analytics'
            ? [
                '12 项',
                '2 项',
                '80%（8 / 10）',
                '90%（9 / 10）',
                '3 份',
                '产品 5 · 市场 4 · 技术 3',
              ][i]
            : '产品部 · ${i == 0 ? '今天' : '本周'}',
        ownerId: resource == 'reviews'
            ? (i == 0 ? 'u2' : session.id)
            : session.id,
        fields: {
          'body': '已整理当前工作进展，下一步需要确认协作安排。相关内容仅供界面演示。',
          'deadline': today.add(const Duration(days: 2)).toIso8601String(),
          'createdAt': DateTime.utc(
            today.year,
            today.month,
            today.day,
            2,
          ).toIso8601String(),
          'type': ['任务', '审批', '日志'][i % 3],
          'reviewState': '待审',
          'sources': ['/item/logs/1', '/item/tasks/1'],
          'events': ['创建任务', '负责人接收'],
          'before': '完成初步调研',
          'after': '完成调研并补充三份访谈记录',
          'businessDate': date,
        },
      ),
    );
  }

  @override
  Future<PageResult> list(String resource, Query query) async {
    await _check(resource);
    if (query.ownerId != null &&
        query.ownerId != session.id &&
        !session.manager) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看他人数据');
    }
    if (scenario == DemoScenario.empty) return const PageResult([]);
    var items = _store
        .putIfAbsent(resource, () => _seed(resource))
        .where((e) => e.title.contains(query.search))
        .toList();
    if (query.from != null && query.to != null) {
      items = items.where((e) {
        final time = DateTime.tryParse('${e.fields['createdAt']}');
        return time == null ||
            (!time.isBefore(query.from!) && time.isBefore(query.to!));
      }).toList();
    }
    return PageResult(items, total: items.length);
  }

  @override
  Future<Record> detail(String resource, String id) async {
    final result = await list(resource, const Query());
    return result.items.firstWhere(
      (e) => e.id == id,
      orElse: () => throw const ApiFailure(FailureKind.notFound, '记录不存在或已归档'),
    );
  }

  @override
  Future<Record> execute(String resource, Command command) async {
    await _check(resource);
    if (resource == 'tasks' &&
        command.action == 'create' &&
        (!session.manager || !session.dispatch)) {
      throw const ApiFailure(FailureKind.forbidden, '当前账号没有任务派发资格');
    }
    if (resource == 'dashboard/company' && !session.manager) {
      throw const ApiFailure(FailureKind.forbidden, '没有公司发布权限');
    }
    if (resource == 'auth' && command.values.containsKey('role')) {
      throw const ApiFailure(FailureKind.forbidden, '注册只能申请员工账号');
    }
    final key = command.idempotencyKey;
    if (key != null && _responses.containsKey(key)) return _responses[key]!;
    final records = _store.putIfAbsent(resource, () => _seed(resource));
    final id = command.values['id'] as String?;
    final index = records.indexWhere((r) => r.id == id);
    if (resource == 'reviews' &&
        index >= 0 &&
        records[index].ownerId == session.id) {
      throw const ApiFailure(FailureKind.forbidden, '不能审核自己的申请');
    }
    if (index >= 0 &&
        command.version != null &&
        command.version != records[index].version) {
      throw const ApiFailure(FailureKind.conflict, '版本已更新，请刷新后重试');
    }
    if (command.action == 'reject' &&
        '${command.values['reason'] ?? ''}'.trim().isEmpty) {
      throw const ApiFailure(FailureKind.validation, '请填写驳回原因');
    }
    final previous = index >= 0 ? records[index] : null;
    final events = List<String>.from(previous?.fields['events'] as List? ?? []);
    events.add(
      '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')} · ${command.action}',
    );
    final result = Record(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: command.values['title'] as String? ?? previous?.title ?? '演示记录',
      subtitle: '仅保存在本次演示中',
      ownerId: previous?.ownerId ?? session.id,
      version: (previous?.version ?? 0) + 1,
      fields: {
        ...?previous?.fields,
        ...command.values,
        'events': events,
        'reviewState': command.action,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (command.action == 'archive' && index >= 0) {
      records.removeAt(index);
    } else if (index >= 0) {
      records[index] = result;
    } else {
      records.insert(0, result);
    }
    if (key != null) _responses[key] = result;
    return result;
  }
}
