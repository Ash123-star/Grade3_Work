import 'dart:convert';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:dio/dio.dart';
import 'package:pandora_mobile/data/models/attachments.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/log_edit_window.dart';
import 'package:pandora_mobile/data/models/task_display.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

enum DemoScenario { normal, empty, offline, forbidden }

String _mockTaskPhase(String status) => switch (status) {
  '待接收' => 'DISPATCHED',
  '进行中' => 'RECEIVED',
  '待验收' => 'FEEDBACK',
  '已验收' => 'ACCEPTED',
  '已归档' => 'ARCHIVED',
  '已撤回' => 'WITHDRAWN',
  '需补充' => 'NEEDS_CHANGES',
  _ => 'UNKNOWN',
};

class DemoAccount {
  const DemoAccount({
    required this.id,
    required this.name,
    required this.role,
    required this.departmentId,
    required this.departmentName,
    required this.teamId,
    required this.teamName,
    required this.managerId,
    required this.intro,
    this.employmentStartDate,
    this.dispatch = false,
    this.companyReviewer = false,
  });

  final String id, name, departmentId, departmentName, teamId, teamName;
  final String managerId, intro;
  final DateTime? employmentStartDate;
  final UserRole role;
  final bool dispatch, companyReviewer;

  Session session({bool? dispatch}) => Session(
    id: id,
    name: name,
    role: role,
    dispatch: dispatch ?? this.dispatch,
    departmentId: departmentId,
    teamId: teamId,
  );

  Record record({
    required int participatingTaskCount,
    required String todayLogStatus,
    required String taskStatus,
  }) {
    final accountIndex = demoAccounts.indexWhere((account) => account.id == id);
    return Record(
      id: id,
      title: name,
      subtitle: '$departmentName · $teamName',
      fields: {
        'body': intro,
        'role': role.name.toUpperCase(),
        'status': 'ACTIVE',
        'dispatch_enabled': dispatch,
        'company_reviewer': companyReviewer,
        'department_id': departmentId,
        'departmentName': departmentName,
        'team_id': teamId,
        'teamName': teamName,
        'managerId': managerId,
        'manager_id': managerId,
        if (employmentStartDate != null)
          'employmentStartDate': employmentStartDate!
              .toIso8601String()
              .split('T')
              .first,
        'phone': '+1 202-555-${(100 + accountIndex).toString()}',
        'email': '${id.replaceAll('-', '.')}@example.invalid',
        'participatingTaskCount': participatingTaskCount,
        'todayLogStatus': todayLogStatus,
        'taskStatus': taskStatus,
      },
    );
  }
}

const demoAccounts = <DemoAccount>[
  DemoAccount(
    id: 'u1',
    name: '林小满',
    role: UserRole.leader,
    departmentId: 'd-product',
    departmentName: '产品部',
    teamId: 't-experience',
    teamName: '产品体验组',
    managerId: 'u-product-dir',
    intro: '负责产品体验与版本节奏，关注方案清晰度和跨团队交付。',
    dispatch: true,
  ),
  DemoAccount(
    id: 'u2',
    name: '陈一诺',
    role: UserRole.employee,
    departmentId: 'd-product',
    departmentName: '产品部',
    teamId: 't-experience',
    teamName: '产品体验组',
    managerId: 'u1',
    intro: '负责需求梳理和用户访谈，把一线反馈整理成可执行的问题清单。',
  ),
  DemoAccount(
    id: 'u3',
    name: '许知远',
    role: UserRole.employee,
    departmentId: 'd-tech',
    departmentName: '技术部',
    teamId: 't-platform',
    teamName: '平台研发组',
    managerId: 'u-tech-lead',
    intro: '负责服务接口与数据模型，重视兼容性、可观测性和故障恢复。',
  ),
  DemoAccount(
    id: 'u4',
    name: '陆星宇',
    role: UserRole.employee,
    departmentId: 'd-product',
    departmentName: '产品部',
    teamId: 't-experience',
    teamName: '产品体验组',
    managerId: 'u1',
    intro: '跟进产品原型和验收口径，擅长把复杂流程拆成清楚步骤。',
  ),
  DemoAccount(
    id: 'u5',
    name: '苏予安',
    role: UserRole.employee,
    departmentId: 'd-product',
    departmentName: '产品部',
    teamId: 't-research',
    teamName: '用户研究组',
    managerId: 'u-research-lead',
    intro: '负责用户研究与可用性观察，持续归纳高频需求和体验风险。',
  ),
  DemoAccount(
    id: 'u6',
    name: '蔡明澄',
    role: UserRole.employee,
    departmentId: 'd-tech',
    departmentName: '技术部',
    teamId: 't-platform',
    teamName: '平台研发组',
    managerId: 'u-tech-lead',
    intro: '负责后端功能开发和接口联调，按契约补齐边界与错误处理。',
  ),
  DemoAccount(
    id: 'u7',
    name: '温以宁',
    role: UserRole.employee,
    departmentId: 'd-tech',
    departmentName: '技术部',
    teamId: 't-quality',
    teamName: '质量保障组',
    managerId: 'u-quality-lead',
    intro: '负责质量保障与回归策略，覆盖核心路径、异常场景和发布风险。',
  ),
  DemoAccount(
    id: 'u8',
    name: '唐星澜',
    role: UserRole.employee,
    departmentId: 'd-market',
    departmentName: '市场运营部',
    teamId: 't-content',
    teamName: '内容运营组',
    managerId: 'u-market-lead',
    intro: '负责产品内容与渠道素材，跟踪发布计划和用户反馈。',
  ),
  DemoAccount(
    id: 'u9',
    name: '顾言',
    role: UserRole.employee,
    departmentId: 'd-market',
    departmentName: '市场运营部',
    teamId: 't-growth',
    teamName: '用户增长组',
    managerId: 'u-growth-lead',
    intro: '负责增长活动和转化数据，按周复盘渠道效果与实验结论。',
  ),
  DemoAccount(
    id: 'u10',
    name: '叶青禾',
    role: UserRole.employee,
    departmentId: 'd-customer',
    departmentName: '客户成功部',
    teamId: 't-delivery',
    teamName: '客户交付组',
    managerId: 'u-customer-lead',
    intro: '负责客户交付与问题跟踪，推动反馈闭环并维护服务质量。',
  ),
  DemoAccount(
    id: 'u-product-dir',
    name: '王若衡',
    role: UserRole.director,
    departmentId: 'd-product',
    departmentName: '产品部',
    teamId: 't-product-office',
    teamName: '产品管理组',
    managerId: 'u-founder',
    intro: '统筹产品路线与跨部门资源，负责阶段目标、风险和交付评审。',
    dispatch: true,
    companyReviewer: true,
  ),
  DemoAccount(
    id: 'u-tech-dir',
    name: '贺知行',
    role: UserRole.director,
    departmentId: 'd-tech',
    departmentName: '技术部',
    teamId: 't-tech-office',
    teamName: '技术管理组',
    managerId: 'u-founder',
    intro: '统筹技术架构、研发能力建设和重点项目交付。',
    dispatch: true,
    companyReviewer: true,
  ),
  DemoAccount(
    id: 'u-market-dir',
    name: '沈嘉禾',
    role: UserRole.director,
    departmentId: 'd-market',
    departmentName: '市场运营部',
    teamId: 't-market-office',
    teamName: '运营管理组',
    managerId: 'u-founder',
    intro: '统筹品牌、内容与用户增长工作，关注渠道投入和结果复盘。',
    dispatch: true,
  ),
  DemoAccount(
    id: 'u-customer-dir',
    name: '周予川',
    role: UserRole.director,
    departmentId: 'd-customer',
    departmentName: '客户成功部',
    teamId: 't-customer-office',
    teamName: '交付管理组',
    managerId: 'u-founder',
    intro: '统筹客户交付、续约风险和跨团队问题处理。',
    dispatch: true,
  ),
  DemoAccount(
    id: 'u-tech-lead',
    name: '周逸飞',
    role: UserRole.leader,
    departmentId: 'd-tech',
    departmentName: '技术部',
    teamId: 't-platform',
    teamName: '平台研发组',
    managerId: 'u-tech-dir',
    intro: '带领平台研发组推进服务改造、接口稳定性和技术债治理。',
    dispatch: true,
  ),
  DemoAccount(
    id: 'u-research-lead',
    name: '许明萱',
    role: UserRole.leader,
    departmentId: 'd-product',
    departmentName: '产品部',
    teamId: 't-research',
    teamName: '用户研究组',
    managerId: 'u-product-dir',
    intro: '带领用户研究组规划访谈、可用性测试和需求证据沉淀。',
    dispatch: true,
  ),
  DemoAccount(
    id: 'u-quality-lead',
    name: '罗景行',
    role: UserRole.leader,
    departmentId: 'd-tech',
    departmentName: '技术部',
    teamId: 't-quality',
    teamName: '质量保障组',
    managerId: 'u-tech-dir',
    intro: '带领质量保障组维护回归策略、缺陷分级和发布质量门禁。',
    dispatch: true,
  ),
  DemoAccount(
    id: 'u-market-lead',
    name: '唐婧',
    role: UserRole.leader,
    departmentId: 'd-market',
    departmentName: '市场运营部',
    teamId: 't-content',
    teamName: '内容运营组',
    managerId: 'u-market-dir',
    intro: '带领内容运营组规划选题、素材生产和渠道发布。',
    dispatch: true,
  ),
  DemoAccount(
    id: 'u-growth-lead',
    name: '沈嘉宁',
    role: UserRole.leader,
    departmentId: 'd-market',
    departmentName: '市场运营部',
    teamId: 't-growth',
    teamName: '用户增长组',
    managerId: 'u-market-dir',
    intro: '带领用户增长组设计实验并跟踪转化漏斗。',
    dispatch: true,
  ),
  DemoAccount(
    id: 'u-customer-lead',
    name: '方可为',
    role: UserRole.leader,
    departmentId: 'd-customer',
    departmentName: '客户成功部',
    teamId: 't-delivery',
    teamName: '客户交付组',
    managerId: 'u-customer-dir',
    intro: '带领客户交付组推进实施计划、培训安排和问题闭环。',
    dispatch: true,
  ),
  DemoAccount(
    id: 'u-founder',
    name: '顾清远',
    role: UserRole.founder,
    departmentId: 'd-executive',
    departmentName: '经营管理层',
    teamId: 't-executive',
    teamName: '经营办公室',
    managerId: '',
    intro: '关注公司经营目标、组织协作和长期产品方向。',
    dispatch: true,
    companyReviewer: true,
  ),
  DemoAccount(
    id: 'u-admin',
    name: '乔安宁',
    role: UserRole.admin,
    departmentId: 'd-admin',
    departmentName: '综合管理部',
    teamId: 't-admin',
    teamName: '组织与信息组',
    managerId: 'u-founder',
    intro: '负责组织配置、账号支持和权限审计，确保管理操作留有依据。',
  ),
];

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
    'tasks/received-card' => 'tasks',
    'organization/dispatch-people' => 'organization',
    _ => r,
  };
  @override
  Future<UploadedAttachment> uploadAttachment(
    SelectedAttachment file, {
    bool aiWork = false,
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
      throw const ApiFailure(FailureKind.notFound, '附件内容暂不可用');
    }
    return DownloadedAttachment(
      name: safeAttachmentName(file.name),
      bytes: file.bytes,
    );
  }

  Future<void> _check(String resource) async {
    if (resource == 'feedback') {
      throw const ApiFailure(FailureKind.notFound, '功能不存在');
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (scenario == DemoScenario.offline) {
      throw const ApiFailure(FailureKind.timeout, '网络连接超时，请重试');
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
    if (resource == 'organization') return _seedAccountRecords(now, instant);
    if (resource == 'organization/profile') {
      return [
        for (final accountRecord in _seedAccountRecords(now, instant))
          Record(
            id: accountRecord.id,
            title: accountRecord.title,
            ownerId: accountRecord.id,
            fields: {
              ...accountRecord.fields,
              '姓名': accountRecord.title,
              '个人介绍': accountRecord.fields['body'],
              '头像': '',
            },
          ),
      ];
    }
    if (resource == 'tasks') return _seedTasks(now, instant);
    if (resource == 'task-labels') {
      final labels = <String, Record>{};
      for (final task in rows('tasks')) {
        final fields = task.fields;
        final id = '${fields['tagId'] ?? ''}';
        if (id.isEmpty) continue;
        labels.putIfAbsent(
          id,
          () => Record(
            id: id,
            title: '${fields['tagName'] ?? ''}',
            fields: {
              'color': fields['tagColor'],
              'category': fields['tagCategory'],
              'status': 'ACTIVE',
            },
          ),
        );
      }
      return labels.values.toList();
    }
    if (resource == 'logs') return _seedLogs(now, instant);
    if (resource == 'dashboard/personal') return _seedPersonalFocus(now);
    if (resource == 'reviews') return _seedReviews(now);
    if (resource == 'notifications') return _seedNotifications(now);
    if (resource == 'audit') return _seedAudit(now);
    if (resource == 'organization/admin') return _seedDepartments();
    if (resource == 'organization/teams') {
      final teams = <String, Record>{};
      for (final account in demoAccounts) {
        teams.putIfAbsent(
          account.teamId,
          () => Record(
            id: account.teamId,
            title: account.teamName,
            fields: {
              'name': account.teamName,
              'department_id': account.departmentId,
              'departmentName': account.departmentName,
              'version': 1,
            },
          ),
        );
      }
      return teams.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    }
    final titles = switch (resource) {
      'dashboard/company' => [
        'Q4 协作工作台体验提升',
        '移动端稳定性与交付质量',
        '重点客户续约与服务复盘',
        '产品发布节奏与跨部门协作',
        '年度安全与权限治理',
      ],
      'ai-maps' => ['确认接口依赖和回退方案', '归纳用户研究共性问题', '为客户交付风险安排负责人'],
      _ => <String>[],
    };
    return [
      for (final (i, title) in titles.indexed)
        Record(
          id: 'company-focus-${i + 1}',
          title: title,
          ownerId: 'u-founder',
          subtitle: '顾清远 · ${stamp(now.subtract(Duration(days: i * 4)))}',
          fields: {
            'body': [
              '对照季度目标梳理产品体验、研发稳定性和客户交付的关键成果。',
              '明确跨部门负责人、时间节点、风险升级路径和验收证据。',
              '结合客户反馈与线上指标安排优先级，逐项跟踪闭环。',
              '建立发布前检查清单，覆盖权限、性能、回滚与沟通准备。',
              '复核组织访问范围、账号状态和高风险操作的审核留痕。',
            ][i],
            'status': '进行中',
            'departmentNames': ['产品部', '技术部', '客户成功部', '市场运营部', '综合管理部'][i],
            'ownerName': ['王若衡', '贺知行', '周予川', '沈嘉禾', '乔安宁'][i],
            'participantIds': [
              [
                'u-product-dir',
                'u-tech-dir',
                'u-customer-dir',
                'u-market-dir',
                'u-admin',
              ][i],
            ],
          },
        ),
    ];
  }

  List<Record> _seedAccountRecords(DateTime now, DateTime instant) {
    final tasks = _seedTasks(now, instant);
    final logs = _seedLogs(now, instant);
    final result = <Record>[];
    for (final account in demoAccounts) {
      final participating = tasks.where(
        (task) => (task.fields['participantIds'] as List? ?? const []).contains(
          account.id,
        ),
      );
      final hasTodayLog = logs.any(
        (log) =>
            log.ownerId == account.id &&
            log.fields['businessDate'] == stamp(now),
      );
      final awaitingReview = participating.any(
        (task) => task.fields['status'] == '待验收',
      );
      result.add(
        account.record(
          participatingTaskCount: participating.length,
          todayLogStatus: hasTodayLog ? '今日日志已提交' : '今日日志待提交',
          taskStatus: awaitingReview ? '有任务待验收' : '任务推进中',
        ),
      );
    }
    return result;
  }

  DemoAccount _account(String id) => demoAccounts.firstWhere(
    (account) => account.id == id,
    orElse: () => demoAccounts.first,
  );

  DateTime _atDay(DateTime day, int hour, [int minute = 0]) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  List<Record> _seedDepartments() => [
    for (final item in const [
      ('d-executive', '经营管理层', '统筹年度经营目标、重点客户和跨部门资源配置。', 'u-founder'),
      ('d-product', '产品部', '负责产品规划、用户研究、体验设计和版本验收。', 'u-product-dir'),
      ('d-tech', '技术部', '负责平台研发、质量保障、基础设施和信息安全。', 'u-tech-dir'),
      ('d-market', '市场运营部', '负责品牌传播、内容运营、渠道增长和活动复盘。', 'u-market-dir'),
      ('d-customer', '客户成功部', '负责客户实施、培训支持、服务质量和续约协作。', 'u-customer-dir'),
      ('d-admin', '综合管理部', '负责组织人事、行政流程、账号支持和权限审计。', 'u-admin'),
    ])
      Record(
        id: item.$1,
        title: item.$2,
        subtitle: item.$3,
        ownerId: item.$4,
        fields: {
          'department_id': item.$1,
          'departmentName': item.$2,
          'status': 'ACTIVE',
          'memberCount': demoAccounts
              .where((a) => a.departmentId == item.$1)
              .length,
          'managerId': item.$4,
          'manager_id': item.$4,
        },
      ),
  ];

  List<Map<String, dynamic>> _seedTeams() {
    final teams = <String, DemoAccount>{};
    for (final account in demoAccounts) {
      teams.putIfAbsent(account.teamId, () => account);
    }
    final result = <Map<String, dynamic>>[];
    for (final entry in teams.entries) {
      final account = entry.value;
      final lead = demoAccounts.firstWhere(
        (candidate) =>
            candidate.teamId == entry.key &&
            candidate.role != UserRole.employee,
        orElse: () => account,
      );
      result.add({
        'id': account.teamId,
        'name': account.teamName,
        'department_id': account.departmentId,
        'managerId': lead.id,
        'manager_id': lead.id,
        'version': 1,
      });
    }
    return result;
  }

  List<Record> _seedPersonalFocus(DateTime now) {
    const focus = [
      '把复杂问题拆成可确认的小步骤',
      '记录一次有效协作中的做法',
      '下次评审先讲清楚决策依据',
      '留出时间复盘今天的取舍',
      '想到一个值得继续验证的问题',
      '记下最近一次工作中的收获',
      '提醒自己及时同步风险变化',
      '整理一个以后可以复用的经验',
      '把未完成的想法留到周末梳理',
      '记录今天值得感谢的一次帮助',
      '给明天的自己留一个行动提示',
      '先确认目标，再决定投入顺序',
      '把反馈中的共性问题记下来',
      '每次交付后补充一条经验',
      '遇到分歧时先对齐事实与目标',
      '记录一个需要持续观察的信号',
      '本周想尝试的一个小改进',
      '为重要决定补上背景和理由',
      '把好用的方法分享给团队',
    ];
    const notes = [
      '这条记录可以继续补充自己的想法、背景或后续行动。',
      '回看这件事时，记下哪些做法有效，以及下次会如何调整。',
      '先保留这个观察，等有更多信息后再决定是否采取行动。',
      '把这次经验整理成自己以后能直接使用的提醒。',
      '如果情况有变化，回来更新这条记录，不必拘泥于固定格式。',
    ];
    return [
      for (final (i, account) in demoAccounts.indexed)
        for (var slot = 0; slot < 2; slot++)
          Record(
            id: 'focus-${account.id}-${slot + 1}',
            title: focus[(i * 2 + slot) % focus.length],
            ownerId: account.id,
            fields: {
              'body': notes[(i + slot) % notes.length],
              '排序位置': slot,
              'pinned': false,
              'createdAt': now
                  .subtract(Duration(days: slot + i % 4))
                  .toIso8601String(),
            },
          ),
    ];
  }

  List<String> _taskTitlesFor(DemoAccount account) =>
      switch (account.departmentId) {
        'd-product' =>
          account.teamId == 't-research'
              ? const ['完成重点用户访谈纪要与需求证据整理', '提交可用性测试问题分级与改进建议']
              : const ['完成产品需求评审与验收口径确认', '跟进版本交互走查和体验问题闭环'],
        'd-tech' =>
          account.teamId == 't-quality'
              ? const ['补齐核心流程回归用例与缺陷复现步骤', '完成发布前质量门禁检查和风险汇总']
              : const ['完成平台接口联调与异常分支验证', '提交服务告警复盘和慢查询优化建议'],
        'd-market' =>
          account.teamId == 't-growth'
              ? const ['复盘渠道转化漏斗并制定下一轮实验', '完成新用户触达活动分组与指标配置']
              : const ['完成本周内容排期和多渠道审核稿', '整理品牌活动素材并提交发布复盘'],
        'd-customer' => const ['完成客户环境部署问题清单与责任分派', '组织客户培训并跟进上线后一周回访'],
        'd-admin' => const ['复核新员工入职资料和部门归属申请', '更新账号权限台账并核对离职回收记录'],
        _ => const ['准备季度经营复盘数据和待决策事项', '协调重点客户续约风险与跨部门资源'],
      };

  List<String> _logWorkFor(
    DemoAccount account,
  ) => switch (account.departmentId) {
    'd-product' =>
      account.teamId == 't-research'
          ? const ['完成 5 位目标用户访谈并归纳共性诉求', '整理可用性测试记录并提交问题优先级', '补充需求证据链接和待确认假设']
          : const ['完成需求评审并更新验收标准', '走查新版本关键页面并登记交互问题', '与研发确认本周版本范围和依赖时间'],
    'd-tech' =>
      account.teamId == 't-quality'
          ? const ['补充登录与任务流程的回归用例', '复现并定位移动端列表分页缺陷', '核对发布候选包的阻断项和回滚步骤']
          : const ['完成组织查询接口联调和错误映射', '排查服务慢查询并提交索引建议', '补充超时重试和权限拒绝场景验证'],
    'd-market' =>
      account.teamId == 't-growth'
          ? const ['复盘注册转化漏斗并标记流失节点', '上线分组触达实验并检查样本口径', '整理渠道获客成本和下周实验假设']
          : const ['完成产品更新说明和渠道素材审核', '排定本周公众号与社群内容发布时间', '汇总活动反馈并整理品牌素材归档'],
    'd-customer' => const [
      '跟进客户测试环境部署并关闭高优问题',
      '完成管理员培训并收集操作反馈',
      '更新客户上线清单和续约风险跟踪项',
    ],
    'd-admin' => const [
      '核对账号归属变更申请及审批记录',
      '完成新员工入职支持和权限开通核验',
      '更新组织通讯录并复核离职账号回收',
    ],
    _ => const ['复核季度经营指标并标注待决策差异', '协调重点客户续约事项和资源负责人', '完成跨部门周会纪要及行动项跟踪'],
  };

  String _initiativeFor(DemoAccount account, int index) {
    final initiatives = switch (account.departmentId) {
      'd-product' => const ['协作工作台改版', 'Q4 产品体验优化'],
      'd-tech' => const ['权限服务升级', '移动端稳定性专项'],
      'd-market' => const ['秋季品牌活动', '渠道增长复盘'],
      'd-customer' => const ['客户 A 上线交付', '重点客户续约支持'],
      'd-admin' => const ['账号治理专项', '新员工入职流程优化'],
      _ => const ['Q4 经营复盘', '重点客户协作计划'],
    };
    return initiatives[index % initiatives.length];
  }

  List<Record> _seedTasks(DateTime now, DateTime instant) {
    const taskCount = 36;
    const statuses = ['待接收', '进行中', '待验收', '需补充', '已验收', '已归档'];
    const tagNames = ['公司重点', '产品体验', '研发质量', '客户交付', '运营计划'];
    const tagColors = ['#FFD9A8', '#CFE5FF', '#DCE8F7', '#F5DDC6', '#E7D4FF'];
    return [
      for (var i = 0; i < taskCount; i++)
        (() {
          final owner = demoAccounts[(i * 7) % demoAccounts.length];
          final taskTitles = _taskTitlesFor(owner);
          final title =
              '${_initiativeFor(owner, i)}：${taskTitles[(i ~/ demoAccounts.length) % taskTitles.length]}';
          final teammates = demoAccounts
              .where(
                (account) =>
                    account.teamId == owner.teamId && account.id != owner.id,
              )
              .take(2)
              .toList();
          final start = DateTime(
            now.year,
            now.month,
            now.day,
          ).add(Duration(days: i % 17 - 8));
          final deadline = _atDay(
            start.add(Duration(days: 1 + i % 3)),
            16 + i % 3,
          );
          final status = statuses[i % statuses.length];
          final dispatchTime = instant
              .subtract(Duration(days: i % 12 + 1))
              .toUtc()
              .toIso8601String();
          final dispatchDay = shanghaiWallTime(DateTime.parse(dispatchTime));
          final phase = _mockTaskPhase(status);
          final receivedAt = phase == 'DISPATCHED'
              ? null
              : dispatchDay
                    .add(const Duration(hours: 4))
                    .toUtc()
                    .toIso8601String();
          final feedbackAt =
              [
                'FEEDBACK',
                'NEEDS_CHANGES',
                'ACCEPTED',
                'ARCHIVED',
              ].contains(phase)
              ? dispatchDay
                    .add(const Duration(days: 1, hours: 2))
                    .toUtc()
                    .toIso8601String()
              : null;
          final acceptedAt = ['ACCEPTED', 'ARCHIVED'].contains(phase)
              ? (i.isEven
                        ? deadline.subtract(const Duration(hours: 2))
                        : deadline.add(const Duration(hours: 2)))
                    .toUtc()
                    .toIso8601String()
              : null;
          final dispatcher = _account(
            owner.managerId.isEmpty ? 'u-founder' : owner.managerId,
          );
          final commentId = 'task-demo-${i + 1}-comment-1';
          return Record(
            id: 'task-demo-${i + 1}',
            title: title,
            ownerId: owner.id,
            subtitle:
                '${owner.departmentName} · ${owner.teamName} · ${stamp(deadline)}',
            fields: {
              'body':
                  '${owner.name}负责$title，交付物为可复核的工作记录和相关依据；跨组依赖由${dispatcher.name}协调。',
              'status': status,
              'phase': phase,
              'startAt': _atDay(start, 9 + i % 3).toIso8601String(),
              'endAt': _atDay(start, 12 + i % 3).toIso8601String(),
              'deadline': deadline.toIso8601String(),
              'createdAt': dispatchTime,
              'dispatchAt': dispatchTime,
              'receivedAt': ?receivedAt,
              'feedbackAt': ?feedbackAt,
              'acceptedAt': ?acceptedAt,
              'dispatcherId': dispatcher.id,
              'participantIds': [owner.id, ...teammates.map((a) => a.id)],
              'participantNames': [owner.name, ...teammates.map((a) => a.name)],
              '所属分组': owner.teamName,
              'departmentId': owner.departmentId,
              'departmentName': owner.departmentName,
              'tagId': [
                'company-important',
                'department-design',
                'department-research',
                'customer-delivery',
                'personal-today',
              ][i % 5],
              'tagName': tagNames[i % 5],
              'tagCategory': i % 5 == 0
                  ? '公司'
                  : i % 5 == 4
                  ? '个人'
                  : '部门',
              'tagColor': tagColors[i % 5],
              'reviewState': status == '待验收' ? '待审' : '已通过',
              '成果说明': '${owner.name}已整理交付材料，待相关人员核对验收清单。',
              'events': [
                '${stamp(start)} · ${dispatcher.name}派发任务',
                '${stamp(start)} · ${owner.name}确认负责人和完成时间',
                if (status == '待验收' || status == '已验收')
                  '${stamp(deadline)} · 提交验收材料',
              ],
              'comments': [
                {
                  'id': commentId,
                  'actorId': dispatcher.id,
                  'actorName': dispatcher.name,
                  'createdAt': _atDay(start, 10, 15).toIso8601String(),
                  'text': '请按${owner.teamName}的交付清单补齐材料，并在截止前同步依赖风险。',
                },
                {
                  'id': 'task-demo-${i + 1}-comment-2',
                  'actorId': owner.id,
                  'actorName': owner.name,
                  'parentCommentId': commentId,
                  'createdAt': _atDay(start, 11, 5).toIso8601String(),
                  'text': '收到，我会先完成${owner.departmentName}范围内的核对，并把待协同事项单独标出。',
                },
              ],
            },
          );
        })(),
    ];
  }

  List<Record> _seedLogs(DateTime now, DateTime instant) {
    return [
      for (final (i, account) in demoAccounts.indexed)
        for (var entry = 0; entry < 3; entry++)
          (() {
            final offset = (i * 3 + entry * 5) % 14;
            final day = DateTime(
              now.year,
              now.month,
              now.day,
            ).subtract(Duration(days: offset));
            final workItems = _logWorkFor(account);
            final work = workItems[entry];
            final next = workItems[(entry + 1) % workItems.length];
            final reviewer = _account(
              account.managerId.isEmpty ? 'u-product-dir' : account.managerId,
            );
            final submitted = offset == 0
                ? instant.subtract(Duration(hours: 1 + i % 5))
                : _atDay(day, 18).toUtc();
            final commentId = 'log-${account.id}-${entry + 1}-comment-1';
            return Record(
              id: 'log-${account.id}-${entry + 1}',
              title: '$work · ${account.name}',
              ownerId: account.id,
              subtitle:
                  '${stamp(day)} · ${account.name} · ${account.departmentName}',
              fields: {
                'body':
                    '${account.name}在${account.teamName}完成$work。相关材料已归档，${(i + entry) % 4 == 0 ? '当前阻碍是等待${account.departmentName}确认依赖时间。' : '本日没有影响排期的阻塞事项。'}',
                '今日工作': work,
                '明日计划': '${account.teamName}继续跟进$next，并同步相关负责人。',
                '遇到的阻碍': (i + entry) % 4 == 0
                    ? '等待${account.departmentName}确认依赖时间。'
                    : '暂无，当前事项按计划推进。',
                '工时': '${6 + (i + entry) % 3}',
                'businessDate': stamp(day),
                'submittedAt': submitted.toIso8601String(),
                'status': '已提交',
                'authorName': account.name,
                'departmentId': account.departmentId,
                'departmentName': account.departmentName,
                'teamId': account.teamId,
                'teamName': account.teamName,
                'participantIds': [account.id],
                'participantNames': [account.name],
                'dispatcherId': account.managerId,
                'tagId': [
                  'department-research',
                  'department-design',
                  'customer-delivery',
                  'personal-today',
                ][(i + entry) % 4],
                'tagName': ['需求评审', '体验设计', '客户交付', '个人计划'][(i + entry) % 4],
                'tagColor': [
                  '#FFD9A8',
                  '#CFE5FF',
                  '#F5DDC6',
                  '#E7D4FF',
                ][(i + entry) % 4],
                'comments': [
                  {
                    'id': commentId,
                    'actorId': reviewer.id,
                    'actorName': reviewer.name,
                    'createdAt': submitted
                        .add(const Duration(minutes: 20))
                        .toIso8601String(),
                    'text': '已看到${account.teamName}的更新，请在明日计划中继续跟进：$next。',
                  },
                  {
                    'id': 'log-${account.id}-${entry + 1}-comment-2',
                    'actorId': account.id,
                    'actorName': account.name,
                    'parentCommentId': commentId,
                    'createdAt': submitted
                        .add(const Duration(minutes: 35))
                        .toIso8601String(),
                    'text': '收到，我会补充进展依据并在下一次同步前更新结果。',
                  },
                ],
              },
            );
          })(),
    ];
  }

  List<Record> _seedReviews(DateTime now) {
    const subjects = [
      '申请调整产品需求验收范围',
      '申请补充客户访谈日志',
      '申请更新平台接口交付时间',
      '申请归档已结束的渠道活动',
      '申请修订质量回归检查项',
      '申请调整客户实施排期',
      '申请新增内容发布审核人',
      '申请更新团队职责说明',
      '申请补录版本风险复盘',
      '申请变更组织成员归属',
      '申请修订用户增长实验目标',
      '申请补充季度经营重点',
    ];
    return [
      for (final (i, subject) in subjects.indexed)
        (() {
          final applicant = demoAccounts[(i * 5 + 1) % demoAccounts.length];
          final founderExempt = applicant.role == UserRole.founder;
          final approver = founderExempt || applicant.managerId.isEmpty
              ? null
              : _account(applicant.managerId);
          final pending = !founderExempt && (approver == null || i % 3 == 0);
          final reviewState = pending
              ? '待审'
              : founderExempt || i % 2 == 0
              ? '已通过'
              : '已驳回';
          return Record(
            id: 'review-demo-${i + 1}',
            title: subject,
            ownerId: applicant.id,
            subtitle:
                '${applicant.name} · ${applicant.departmentName} · ${stamp(now.subtract(Duration(days: i)))}',
            fields: {
              'applicantName': applicant.name,
              'reviewerName': approver?.name,
              'reviewerId': approver?.id,
              'reviewerConfigured': approver != null,
              'approvalMode': 'DIRECT_MANAGER',
              'reviewState': reviewState,
              if (founderExempt) 'decisionSource': 'FOUNDER_EXEMPT',
              'targetResource': i % 2 == 0 ? 'tasks' : 'logs',
              'targetId': i % 2 == 0
                  ? 'task-demo-${i + 1}'
                  : 'log-${applicant.id}-1',
              'reason': '${applicant.name}说明了业务背景、影响范围和期望生效时间，等待直属上级核对。',
              'before': '当前已生效内容保持不变。',
              'after': '按申请补充交付范围、记录或组织说明。',
              'step': 0,
              'createdAt': now.subtract(Duration(days: i)).toIso8601String(),
              'reviewEvents': [
                '${applicant.name}提交申请',
                if (founderExempt) '系统 · 创始人授权操作免审并自动批准',
                if (!pending && !founderExempt && approver != null)
                  '${approver.name}${reviewState == '已通过' ? '通过' : '驳回'}',
              ],
            },
          );
        })(),
    ];
  }

  List<Record> _seedNotifications(DateTime now) => [
    for (final (i, account) in demoAccounts.indexed)
      Record(
        id: 'notice-${account.id}',
        title: [
          '${account.name}有一项任务需要关注',
          '${account.departmentName}的周报已提交',
          '收到${_account(account.managerId.isEmpty ? 'u-founder' : account.managerId).name}的工作提醒',
        ][i % 3],
        ownerId: account.id,
        subtitle:
            '${stamp(now.subtract(Duration(hours: i * 3)))} · ${account.departmentName}',
        fields: {
          'type': ['任务', '日志', '评论'][i % 3],
          'targetResource': ['tasks', 'logs', 'reviews'][i % 3],
          'targetId': [
            'task-demo-${i + 1}',
            'log-${account.id}-1',
            'review-demo-${i % 12 + 1}',
          ][i % 3],
          'read': i % 4 == 0,
          'actorName': _account(
            account.managerId.isEmpty ? 'u-founder' : account.managerId,
          ).name,
          'createdAt': now.subtract(Duration(hours: i * 3)).toIso8601String(),
        },
      ),
  ];

  List<Record> _seedAudit(DateTime now) => [
    for (final (i, account)
        in demoAccounts.where((a) => a.role != UserRole.employee).indexed)
      Record(
        id: 'audit-demo-${i + 1}',
        title: [
          '${account.name}复核部门成员归属',
          '${account.name}提交任务审核策略调整',
          '${account.name}确认账号状态复核结果',
          '${account.name}更新组织工作职责说明',
        ][i % 4],
        ownerId: account.id,
        subtitle:
            '${stamp(now.subtract(Duration(days: i + 1)))} · ${account.role.label}',
        fields: {
          'actorId': account.id,
          'actorName': account.name,
          'role': account.role.name.toUpperCase(),
          'action': ['组织复核', '提交审核', '账号检查', '资料更新'][i % 4],
          'targetResource': i.isEven ? 'organization/admin' : 'reviews',
          'targetId': i.isEven ? account.departmentId : 'review-demo-${i + 1}',
          'createdAt': now.subtract(Duration(days: i + 1)).toIso8601String(),
        },
      ),
  ];

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
    var items = rows(resource).where(
      (r) =>
          (resource == 'logs' || resource == 'logs/subordinates'
                  ? '${r.title} ${r.subtitle} ${r.fields['authorName'] ?? ''} ${r.fields['今日工作'] ?? r.fields['body'] ?? ''}'
                  : '${r.title}${r.subtitle}')
              .toLowerCase()
              .contains(query.search.toLowerCase()),
    );
    if (resource == 'organization') {
      items = items.where((r) => visiblePeople.contains(r.id));
    }
    if (resource == 'organization/profile') {
      items = items.where((r) => visiblePeople.contains(r.id));
    }
    if (resource == 'organization/teams' &&
        session.role != UserRole.admin &&
        session.role != UserRole.founder) {
      final account = _account(session.id);
      items = items.where(
        (r) => session.role == UserRole.director
            ? r.fields['department_id'] ==
                  (session.departmentId ?? account.departmentId)
            : r.id == (session.teamId ?? account.teamId),
      );
    }
    if (resource == 'tasks' || resource == 'tasks/received-card') {
      items = items.where(taskVisible);
      if (query.ownerId != null) {
        items = items.where((record) => record.ownerId == query.ownerId);
      }
      if (resource == 'tasks/received-card') {
        items = items.where((record) {
          final participants = record.fields['participantIds'] as List?;
          final received = participants == null
              ? record.ownerId == session.id
              : participants.map((id) => '$id').contains(session.id);
          return received &&
              '${record.fields['dispatcherId'] ?? ''}' != session.id;
        });
      }
    }
    if (resource == 'logs/subordinates') {
      items = items.where(
        (r) =>
            r.ownerId != session.id &&
            visiblePeople.contains(r.ownerId) &&
            isSubmittedDiary(r),
      );
    }
    if (['logs', 'dashboard/personal', 'private-notes'].contains(resource)) {
      items = items.where((r) => r.ownerId == (query.ownerId ?? session.id));
    }
    if (resource == 'logs/subordinates' && query.ownerId != null) {
      items = items.where((r) => r.ownerId == query.ownerId);
    }
    if (resource == 'logs/subordinates' && query.departmentId != null) {
      items = items.where(
        (r) =>
            '${r.fields['departmentId'] ?? r.fields['department_id'] ?? ''}' ==
            query.departmentId,
      );
    }
    if (resource == 'organization/dispatch-people') {
      if (!session.manager || !session.dispatch) {
        throw const ApiFailure(FailureKind.forbidden, '没有派发资格');
      }
      items = items.where((p) => p.fields['status'] == 'ACTIVE');
    }
    if ((resource == 'tasks' || resource == 'tasks/received-card') &&
        !session.manager) {
      items = items.where((r) {
        final participants = (r.fields['participantIds'] as List?)
            ?.map((id) => '$id')
            .toSet();
        return r.ownerId == session.id ||
            participants?.contains(session.id) == true ||
            '${r.fields['dispatcherId'] ?? ''}' == session.id;
      });
    }
    if (resource == 'reviews') {
      items = items.where(
        (record) =>
            record.ownerId == session.id ||
            record.fields['reviewerId'] == session.id,
      );
    }
    if (resource == 'notifications') {
      items = items.where((r) => r.ownerId == session.id);
    }
    if (query.from != null && query.to != null) {
      var rangeFrom = query.from!;
      var rangeTo = query.to!;
      if (resource == 'tasks' && rangeTo.difference(rangeFrom).inDays >= 28) {
        final monthStart = shanghaiWallTime(rangeFrom);
        final monthEnd = shanghaiWallTime(rangeTo);
        final visibleStart = DateTime(
          monthStart.year,
          monthStart.month,
          monthStart.day,
        ).subtract(Duration(days: monthStart.weekday - 1));
        final visibleEnd = DateTime(
          monthEnd.year,
          monthEnd.month,
          monthEnd.day,
        ).add(Duration(days: (8 - monthEnd.weekday) % 7));
        rangeFrom = DateTime.utc(
          visibleStart.year,
          visibleStart.month,
          visibleStart.day,
        ).subtract(const Duration(hours: 8));
        rangeTo = DateTime.utc(
          visibleEnd.year,
          visibleEnd.month,
          visibleEnd.day,
        ).subtract(const Duration(hours: 8));
      }
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
              !deadline.isBefore(start) &&
              start.isBefore(rangeTo) &&
              !deadline.isBefore(rangeFrom);
        }
        final raw = resource.startsWith('logs')
            ? '${r.fields['businessDate']}T00:00:00+08:00'
            : '${r.fields['deadline'] ?? r.fields['createdAt']}';
        final date = parseBusinessInstant(raw);
        return date != null &&
            !date.isBefore(rangeFrom) &&
            date.isBefore(rangeTo);
      });
    }
    final result = items
        .map(
          (item) => resource == 'tasks' || resource == 'tasks/received-card'
              ? _withTaskDisplay(item)
              : item,
        )
        .toList();
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
  Future<MemberLogMonth> memberLogMonth(String ownerId, DateTime month) async {
    await _check('logs/subordinates');
    if (!session.manager || !visiblePeople.contains(ownerId)) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看该成员日志日历');
    }
    final start = DateTime(month.year, month.month);
    final now = shanghaiWallTime(clock());
    final employmentStart =
        _account(ownerId).employmentStartDate ?? DateTime(2025, 1, 1);
    final submitted = rows('logs')
        .where(
          (record) => record.ownerId == ownerId && isSubmittedDiary(record),
        )
        .where((record) {
          final date = DateTime.tryParse('${record.fields['businessDate']}');
          return date != null &&
              date.year == start.year &&
              date.month == start.month;
        })
        .map((record) => DateTime.tryParse('${record.fields['businessDate']}'))
        .whereType<DateTime>()
        .map((date) => date.day)
        .toSet();
    return MemberLogMonth(
      ownerId: ownerId,
      month: start,
      employmentStartDate: employmentStart,
      days: {
        for (
          var day = 1;
          day <= DateTime(start.year, start.month + 1, 0).day;
          day++
        )
          day: (() {
            final date = DateTime(start.year, start.month, day);
            if (date.isAfter(DateTime(now.year, now.month, now.day))) {
              return MemberLogDayStatus.future;
            }
            if (date.isBefore(employmentStart)) {
              return MemberLogDayStatus.unknown;
            }
            return submitted.contains(day)
                ? MemberLogDayStatus.submitted
                : MemberLogDayStatus.missing;
          })(),
      },
    );
  }

  @override
  Future<Record> analytics(AnalyticsQuery query) async {
    await _check('analytics');
    if (!['day', 'week', 'month'].contains(query.period) ||
        !['department', 'team', 'person'].contains(query.groupBy)) {
      throw const ApiFailure(FailureKind.validation, '统计周期或分组维度无效');
    }
    final date = DateTime(query.date.year, query.date.month, query.date.day);
    var start = date;
    if (query.period == 'week') {
      start = date.subtract(Duration(days: date.weekday - 1));
    } else if (query.period == 'month') {
      start = DateTime(date.year, date.month);
    }
    final end = query.period == 'month'
        ? DateTime(start.year, start.month + 1)
        : start.add(Duration(days: query.period == 'week' ? 7 : 1));
    final organization = rows('organization');
    final availablePeople = organization
        .where((person) => visiblePeople.contains(person.id))
        .toList();
    final departmentIds = availablePeople
        .map((person) => '${person.fields['department_id'] ?? ''}')
        .toSet();
    final teamIds = availablePeople
        .map((person) => '${person.fields['team_id'] ?? ''}')
        .toSet();
    if (query.departmentId != null &&
            !departmentIds.contains(query.departmentId) ||
        query.teamId != null && !teamIds.contains(query.teamId) ||
        query.ownerId != null && !visiblePeople.contains(query.ownerId)) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看所选统计范围');
    }
    final people = availablePeople.where((person) {
      return (query.departmentId == null ||
              '${person.fields['department_id'] ?? ''}' ==
                  query.departmentId) &&
          (query.teamId == null ||
              '${person.fields['team_id'] ?? ''}' == query.teamId) &&
          (query.ownerId == null || person.id == query.ownerId);
    }).toList();
    final personIds = people.map((person) => person.id).toSet();
    final tasks = rows(
      'tasks',
    ).where((task) => personIds.contains(task.ownerId)).toList();
    final logs = rows('logs')
        .where(
          (log) => personIds.contains(log.ownerId) && isSubmittedDiary(log),
        )
        .toList();

    DateTime? wallDate(dynamic raw) {
      final instant = businessEventTime(raw);
      return instant == null
          ? null
          : DateTime(instant.year, instant.month, instant.day);
    }

    bool inRange(DateTime? value) =>
        value != null && !value.isBefore(start) && value.isBefore(end);
    const completedPhases = ['ACCEPTED', 'ARCHIVED', '已验收', '已归档'];
    final dispatched = tasks
        .where((task) => inRange(wallDate(task.fields['dispatchAt'])))
        .toList();
    final accepted = tasks
        .where(
          (task) =>
              completedPhases.contains(
                '${task.fields['phase'] ?? task.fields['status']}',
              ) &&
              inRange(wallDate(task.fields['acceptedAt'])),
        )
        .toList();
    final onTime = accepted.where((task) {
      final acceptedAt = wallDate(task.fields['acceptedAt']);
      final deadline = wallDate(task.fields['deadline']);
      return acceptedAt != null &&
          deadline != null &&
          !acceptedAt.isAfter(deadline);
    }).length;
    final now = shanghaiWallTime(clock());
    final today = DateTime(now.year, now.month, now.day);
    final overdue = tasks.where((task) {
      final due = wallDate(task.fields['deadline']);
      final completed = [
        'ACCEPTED',
        'ARCHIVED',
        '已验收',
        '已归档',
      ].contains('${task.fields['phase'] ?? task.fields['status']}');
      return inRange(due) && due!.isBefore(today) && !completed;
    }).length;
    final submittedLogs = logs.where((log) {
      final day = DateTime.tryParse('${log.fields['businessDate'] ?? ''}');
      return day != null && !day.isBefore(start) && day.isBefore(end);
    }).toList();
    final eligiblePeople = people.length;
    final elapsedEnd = end.isAfter(today.add(const Duration(days: 1)))
        ? today.add(const Duration(days: 1))
        : end;
    final elapsedDays = elapsedEnd
        .difference(start)
        .inDays
        .clamp(0, 366)
        .toInt();
    final diaryDenominator = eligiblePeople * elapsedDays;
    final diaryRate = diaryDenominator == 0
        ? null
        : submittedLogs.length / diaryDenominator;

    final groups = <String, List<Record>>{};
    for (final person in people) {
      final groupId = switch (query.groupBy) {
        'team' => '${person.fields['team_id'] ?? ''}',
        'person' => person.id,
        _ => '${person.fields['department_id'] ?? ''}',
      };
      if (groupId.isNotEmpty) groups.putIfAbsent(groupId, () => []).add(person);
    }
    final groupedComparison = [
      for (final entry in groups.entries)
        () {
          final ids = entry.value.map((person) => person.id).toSet();
          final groupTasks = tasks.where((task) => ids.contains(task.ownerId));
          final groupDispatched = groupTasks
              .where((task) => inRange(wallDate(task.fields['dispatchAt'])))
              .length;
          final groupAcceptedTasks = groupTasks
              .where(
                (task) =>
                    completedPhases.contains(
                      '${task.fields['phase'] ?? task.fields['status']}',
                    ) &&
                    inRange(wallDate(task.fields['acceptedAt'])),
              )
              .toList();
          final groupAccepted = groupAcceptedTasks.length;
          final groupReceived = groupTasks
              .where((task) => inRange(wallDate(task.fields['receivedAt'])))
              .length;
          final groupFeedback = groupTasks
              .where((task) => inRange(wallDate(task.fields['feedbackAt'])))
              .length;
          final groupLogs = submittedLogs
              .where((log) => ids.contains(log.ownerId))
              .length;
          final groupDiaryDenominator = entry.value.length * elapsedDays;
          final groupOnTime = groupAcceptedTasks.where((task) {
            final acceptedAt = wallDate(task.fields['acceptedAt']);
            final deadline = wallDate(task.fields['deadline']);
            return acceptedAt != null &&
                deadline != null &&
                !acceptedAt.isAfter(deadline);
          }).length;
          final groupOverdue = groupTasks.where((task) {
            final due = wallDate(task.fields['deadline']);
            final complete = completedPhases.contains(
              '${task.fields['phase'] ?? task.fields['status']}',
            );
            return inRange(due) && due!.isBefore(today) && !complete;
          }).length;
          final person = entry.value.first;
          final groupName = switch (query.groupBy) {
            'team' =>
              person.fields['teamName'] ??
                  person.fields['team_name'] ??
                  entry.key,
            'person' => person.title,
            _ =>
              person.fields['departmentName'] ??
                  person.fields['部门'] ??
                  entry.key,
          };
          return {
            'groupId': entry.key,
            'groupBy': query.groupBy,
            'groupName': groupName,
            'departmentId': query.groupBy == 'department' ? entry.key : null,
            'teamId': query.groupBy == 'team' ? entry.key : null,
            'ownerId': query.groupBy == 'person' ? entry.key : null,
            'dispatched': groupDispatched,
            'received': groupReceived,
            'feedback': groupFeedback,
            'accepted': groupAccepted,
            'onTimeAccepted': groupOnTime,
            'onTimeDenominator': groupAccepted,
            'onTimeRate': groupAccepted == 0
                ? null
                : groupOnTime / groupAccepted,
            'overdue': groupOverdue,
            'diarySubmitted': groupLogs,
            'diaryDenominator': groupDiaryDenominator,
            'diaryRate': groupDiaryDenominator == 0
                ? null
                : groupLogs / groupDiaryDenominator,
          };
        }(),
    ];

    final phaseCounts = <String, int>{};
    for (final task in dispatched) {
      final phase = '${task.fields['phase'] ?? task.fields['status']}';
      final label = switch (phase) {
        'DISPATCHED' || '待接收' => '待接收',
        'RECEIVED' || '进行中' => '进行中',
        'FEEDBACK' || '待验收' => '待验收',
        'ACCEPTED' || '已验收' => '已验收',
        'ARCHIVED' || '已归档' => '已归档',
        'WITHDRAWN' || '已撤回' => '已撤回',
        'NEEDS_CHANGES' || '需补充' => '需补充',
        _ => '其他',
      };
      phaseCounts.update(label, (count) => count + 1, ifAbsent: () => 1);
    }

    final trend = <Map<String, dynamic>>[];
    for (
      var day = start;
      day.isBefore(end);
      day = day.add(const Duration(days: 1))
    ) {
      final dayDispatch = dispatched
          .where((task) => wallDate(task.fields['dispatchAt']) == day)
          .length;
      final dayReceived = tasks
          .where((task) => wallDate(task.fields['receivedAt']) == day)
          .length;
      final dayFeedback = tasks
          .where((task) => wallDate(task.fields['feedbackAt']) == day)
          .length;
      final dayAccepted = tasks
          .where(
            (task) =>
                completedPhases.contains(
                  '${task.fields['phase'] ?? task.fields['status']}',
                ) &&
                wallDate(task.fields['acceptedAt']) == day,
          )
          .length;
      final dayOverdue = tasks.where((task) {
        final due = wallDate(task.fields['deadline']);
        final complete = completedPhases.contains(
          '${task.fields['phase'] ?? task.fields['status']}',
        );
        return due == day &&
            !complete &&
            day.isBefore(today.add(const Duration(days: 1)));
      }).length;
      final dayLogs = submittedLogs
          .where((log) => log.fields['businessDate'] == stamp(day))
          .map((log) => log.ownerId)
          .toSet()
          .length;
      trend.add({
        'date': stamp(day),
        'dispatched': dayDispatch,
        'received': dayReceived,
        'feedback': dayFeedback,
        'accepted': dayAccepted,
        'overdue': dayOverdue,
        'diarySubmitted': dayLogs,
        'diaryDenominator': eligiblePeople,
        'diaryRate': eligiblePeople == 0 ? null : dayLogs / eligiblePeople,
      });
    }
    final phaseDistribution = phaseCounts.entries
        .map((entry) => {'phase': entry.key, 'count': entry.value})
        .toList();
    return Record(
      id: 'analytics',
      title: '工作统计',
      fields: {
        'range': {'first': stamp(start), 'end': stamp(end)},
        'updatedAt': clock().toUtc().toIso8601String(),
        'filters': query.toJson(),
        'dispatched': dispatched.length,
        'overdue': overdue,
        'received': trend.fold<int>(
          0,
          (sum, point) => sum + ((point['received'] as num?)?.toInt() ?? 0),
        ),
        'feedback': trend.fold<int>(
          0,
          (sum, point) => sum + ((point['feedback'] as num?)?.toInt() ?? 0),
        ),
        'onTimeAcceptance': {
          'numerator': onTime,
          'denominator': accepted.length,
          'rate': accepted.isEmpty ? null : onTime / accepted.length,
          'definition': '所选周期内已验收且实际验收日期不晚于任务截止日期的比例',
        },
        'dailySubmission': {
          'numerator': submittedLogs.length,
          'denominator': diaryDenominator,
          'rate': diaryRate,
          'definition': '范围内已提交日志人数日 / 授权成员数与范围内已到日期数',
        },
        'groupBy': query.groupBy,
        'groupedComparison': groupedComparison,
        'departmentComparison': groupedComparison,
        'taskPhaseDistribution': phaseDistribution,
        'trend': trend,
        'dailyTrend': trend,
      },
    );
  }

  @override
  Future<PageResult> analyticsDetails(AnalyticsDetailsQuery query) async {
    await _check('analytics');
    const allowedMetrics = {
      'dispatched',
      'received',
      'feedback',
      'accepted',
      'overdue',
      'diarySubmitted',
      'onTimeAcceptance',
      'phase:待接收',
      'phase:进行中',
      'phase:待验收',
      'phase:已验收',
      'phase:已归档',
      'phase:已撤回',
      'phase:需补充',
      'phase:其他',
    };
    if (!['day', 'week', 'month'].contains(query.period) ||
        !['department', 'team', 'person'].contains(query.groupBy) ||
        !allowedMetrics.contains(query.metric) ||
        query.limit < 1 ||
        query.limit > 100) {
      throw const ApiFailure(FailureKind.validation, '统计明细条件无效');
    }
    final date = DateTime(query.date.year, query.date.month, query.date.day);
    var start = date;
    if (query.period == 'week') {
      start = date.subtract(Duration(days: date.weekday - 1));
    } else if (query.period == 'month') {
      start = DateTime(date.year, date.month);
    }
    final end = query.period == 'month'
        ? DateTime(start.year, start.month + 1)
        : start.add(Duration(days: query.period == 'week' ? 7 : 1));
    final now = shanghaiWallTime(clock());
    final today = DateTime(now.year, now.month, now.day);
    final visible = rows(
      'organization',
    ).where((person) => visiblePeople.contains(person.id));
    if ((query.departmentId != null &&
            !visible.any(
              (p) => '${p.fields['department_id'] ?? ''}' == query.departmentId,
            )) ||
        (query.teamId != null &&
            !visible.any(
              (p) => '${p.fields['team_id'] ?? ''}' == query.teamId,
            )) ||
        (query.ownerId != null && !visiblePeople.contains(query.ownerId))) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看所选统计范围');
    }
    final people = visible
        .where(
          (person) =>
              (query.departmentId == null ||
                  '${person.fields['department_id'] ?? ''}' ==
                      query.departmentId) &&
              (query.teamId == null ||
                  '${person.fields['team_id'] ?? ''}' == query.teamId) &&
              (query.ownerId == null || person.id == query.ownerId),
        )
        .toList();
    final peopleById = {for (final person in people) person.id: person};
    bool groupIdIsVisible(Record person) => switch (query.groupBy) {
      'team' => '${person.fields['team_id'] ?? ''}' == query.groupId,
      'person' => person.id == query.groupId,
      _ => '${person.fields['department_id'] ?? ''}' == query.groupId,
    };
    if (query.groupId != null && !people.any(groupIdIsVisible)) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看所选统计分组');
    }
    String groupIdOf(Record record) {
      final person = peopleById[record.ownerId];
      if (person == null) return '';
      return switch (query.groupBy) {
        'team' => '${person.fields['team_id'] ?? ''}',
        'person' => person.id,
        _ => '${person.fields['department_id'] ?? ''}',
      };
    }

    DateTime? businessDay(dynamic raw) {
      final instant = businessEventTime(raw);
      return instant == null
          ? null
          : DateTime(instant.year, instant.month, instant.day);
    }

    bool inRange(DateTime? day) =>
        day != null && !day.isBefore(start) && day.isBefore(end);
    bool matchesBucket(dynamic raw) =>
        query.bucket == null ||
        (businessDay(raw) != null && stamp(businessDay(raw)!) == query.bucket);
    bool matchesGroup(Record record) =>
        peopleById.containsKey(record.ownerId) &&
        (query.groupId == null || groupIdOf(record) == query.groupId);
    final candidates = <Record>[];
    final completePhases = {'ACCEPTED', 'ARCHIVED', '已验收', '已归档'};
    for (final task in rows('tasks')) {
      if (!matchesGroup(task)) continue;
      final phase = '${task.fields['phase'] ?? task.fields['status']}';
      final dispatchDay = businessDay(task.fields['dispatchAt']);
      final receivedDay = businessDay(task.fields['receivedAt']);
      final feedbackDay = businessDay(task.fields['feedbackAt']);
      final acceptedDay = businessDay(task.fields['acceptedAt']);
      final deadline = DateTime.tryParse('${task.fields['deadline'] ?? ''}');
      final complete = completePhases.contains(phase);
      final matches = switch (query.metric) {
        'dispatched' =>
          inRange(dispatchDay) && matchesBucket(task.fields['dispatchAt']),
        'received' =>
          inRange(receivedDay) && matchesBucket(task.fields['receivedAt']),
        'feedback' =>
          inRange(feedbackDay) && matchesBucket(task.fields['feedbackAt']),
        'accepted' =>
          complete &&
              inRange(acceptedDay) &&
              matchesBucket(task.fields['acceptedAt']),
        'onTimeAcceptance' =>
          complete &&
              inRange(acceptedDay) &&
              deadline != null &&
              task.fields['acceptedAt'] != null &&
              !DateTime.parse(
                '${task.fields['acceptedAt']}',
              ).isAfter(deadline) &&
              matchesBucket(task.fields['acceptedAt']),
        'overdue' =>
          deadline != null &&
              inRange(businessDay(deadline)) &&
              businessDay(deadline)!.isBefore(today) &&
              !complete &&
              matchesBucket(deadline),
        _ when query.metric.startsWith('phase:') =>
          inRange(dispatchDay) &&
              phase ==
                  (switch (query.metric.substring(6)) {
                    '待接收' => 'DISPATCHED',
                    '进行中' => 'RECEIVED',
                    '待验收' => 'FEEDBACK',
                    '已验收' => 'ACCEPTED',
                    '已归档' => 'ARCHIVED',
                    '已撤回' => 'WITHDRAWN',
                    '需补充' => 'NEEDS_CHANGES',
                    _ => query.metric.substring(6),
                  }) &&
              matchesBucket(task.fields['dispatchAt']),
        _ => false,
      };
      if (matches) candidates.add(task);
    }
    if (query.metric == 'diarySubmitted') {
      for (final log in rows('logs')) {
        if (!matchesGroup(log) || !isSubmittedDiary(log)) continue;
        final day = DateTime.tryParse('${log.fields['businessDate'] ?? ''}');
        if (inRange(day) && matchesBucket(day)) candidates.add(log);
      }
    }
    candidates.sort((a, b) => a.title.compareTo(b.title));
    final offset = int.tryParse(query.cursor ?? '0') ?? 0;
    final page = candidates.skip(offset).take(query.limit).toList();
    final nextOffset = offset + page.length;
    return PageResult(
      page,
      total: candidates.length,
      nextCursor: nextOffset < candidates.length ? '$nextOffset' : null,
    );
  }

  @override
  Future<Record> detail(String resource, String id, {String? ownerId}) async {
    await _check(resource);
    if (resource == 'organization/tree') {
      return Record(
        id: 'tree',
        title: '组织架构',
        fields: {
          'departments': [
            for (final department in rows('organization/admin'))
              {
                'id': department.id,
                'name': department.title,
                'managerId': department.fields['managerId'],
                'manager_id': department.fields['manager_id'],
                'version': department.version,
              },
          ],
          'teams': _seedTeams(),
          'people': rows('organization'),
        },
      );
    }
    if (resource == 'organization/policy') {
      if (!session.administrator) {
        throw const ApiFailure(FailureKind.forbidden, '仅管理员可配置');
      }
      return const Record(
        id: 'policy',
        title: '直属上级单级审核',
        fields: {
          'approval_mode': 'DIRECT_MANAGER',
          'reviewer_rule': 'CONFIGURED_DIRECT_MANAGER',
          'unconfigured_behavior': 'PENDING',
          'founder_behavior': 'FOUNDER_EXEMPT',
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
    if (resource == 'organization/profile' &&
        !visiblePeople.contains(item.id)) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看该成员资料');
    }
    if (['logs', 'logs/subordinates', 'tasks', 'reviews'].contains(resource) &&
        !session.manager &&
        item.ownerId != session.id &&
        !(resource == 'tasks' && taskVisible(item))) {
      throw const ApiFailure(FailureKind.forbidden, '无权查看其他成员的记录');
    }
    if (['dashboard/personal', 'private-notes'].contains(resource) &&
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
          'canWithdraw': false,
          'serverNow': clock().toUtc().toIso8601String(),
        },
      );
    }
    return resource == 'tasks' ? _withTaskDisplay(item) : item;
  }

  Map<String, dynamic> _taskDisplayFields(Map<String, dynamic> fields) {
    final label = rows(
      'task-labels',
    ).where((label) => label.id == fields['tagId']).firstOrNull;
    return {
      'tagName': label?.title ?? taskTagLabel(fields),
      if (label != null) 'tagColor': label.fields['color'],
      'participantNames': taskParticipantNames(
        fields,
        namesById: {
          for (final person in rows('organization')) person.id: person.title,
        },
      ),
    };
  }

  Record _withTaskDisplay(Record item) => Record(
    id: item.id,
    title: item.title,
    subtitle: item.subtitle,
    ownerId: item.ownerId,
    version: item.version,
    fields: {...item.fields, ..._taskDisplayFields(item.fields)},
  );

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

  DemoAccount? _directManager(String ownerId) {
    final owner = demoAccounts
        .where((account) => account.id == ownerId)
        .firstOrNull;
    if (owner == null ||
        owner.managerId.isEmpty ||
        owner.managerId == ownerId) {
      return null;
    }
    final manager = demoAccounts
        .where((account) => account.id == owner.managerId)
        .firstOrNull;
    if (manager == null || manager.id == owner.id) return null;
    return manager;
  }

  Record _applyReviewCandidate({
    required String resource,
    required String? id,
    required String ownerId,
    required Map<String, dynamic> candidate,
    int? baseVersion,
  }) {
    final target = rows(resource);
    final index = target.indexWhere((record) => record.id == id);
    final existing = index < 0 ? null : target[index];
    if (baseVersion != null &&
        (existing == null || existing.version != baseVersion)) {
      throw const ApiFailure(FailureKind.conflict, '原记录已更新，请重新读取后重试');
    }
    final base =
        existing ??
        Record(
          id: id ?? 'p${clock().microsecondsSinceEpoch}',
          title: '${candidate['title'] ?? '新记录'}',
          ownerId: ownerId,
        );
    final updated = copy(base, {
      ...candidate,
      'body': candidate['内容'] ?? candidate['今日工作'] ?? base.fields['body'] ?? '',
      'status': candidate['status'] ?? base.fields['status'] ?? '已提交',
      'versions': [
        ...?base.fields['versions'] as List?,
        {
          'version': base.version + 1,
          'body': candidate['今日工作'] ?? candidate['内容'] ?? '',
          'time': clock().toIso8601String(),
        },
      ],
    }, title: candidate['title'] as String?);
    if (index < 0) {
      target.insert(0, updated);
    } else {
      target[index] = updated;
    }
    return updated;
  }

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
    final v = command.values;
    final action = resource == 'logs' && command.action == 'update' ? 'update-content' : command.action;
    final key = command.idempotencyKey;
    if (key != null && store.responses.containsKey(key)) {
      return store.responses[key]!;
    }
    if (resource == 'auth') {
      if (v.containsKey('role')) {
        throw const ApiFailure(FailureKind.forbidden, '注册只能申请员工账号');
      }
      return const Record(id: 'auth', title: '登录成功');
    }
    if (resource == 'analytics/export') {
      final date = DateTime.tryParse('${v['date'] ?? ''}');
      final period = '${v['period'] ?? ''}';
      final target = '${v['resource'] ?? ''}';
      final groupBy = '${v['groupBy'] ?? 'department'}';
      if (date == null ||
          !['day', 'week', 'month'].contains(period) ||
          !['tasks', 'logs'].contains(target) ||
          !['department', 'team', 'person'].contains(groupBy)) {
        throw const ApiFailure(FailureKind.validation, '统计导出条件无效');
      }
      final metric = target == 'tasks' ? 'dispatched' : 'diarySubmitted';
      var cursor = '0';
      final output = StringBuffer('id,title,ownerId,metric,date\r\n');
      do {
        final page = await analyticsDetails(
          AnalyticsDetailsQuery(
            date: date,
            period: period,
            groupBy: groupBy,
            departmentId: v['departmentId'] as String?,
            teamId: v['teamId'] as String?,
            ownerId: v['ownerId'] as String?,
            metric: metric,
            cursor: cursor,
            limit: 100,
          ),
        );
        for (final item in page.items) {
          final value = [
            item.id,
            item.title,
            item.ownerId,
            metric,
            item.fields['dispatchAt'] ?? item.fields['businessDate'] ?? '',
          ];
          output.writeln(
            value.map((cell) => '"${'$cell'.replaceAll('"', '""')}"').join(','),
          );
        }
        cursor = page.nextCursor ?? '';
      } while (cursor.isNotEmpty);
      return Record(
        id: 'analytics-export',
        title: '统计导出',
        fields: {'bytes': utf8.encode(output.toString())},
      );
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
      if (action == 'policy') {
        throw const ApiFailure(
          FailureKind.unavailable,
          '审核方式由组织直属关系确定，不再配置团队或部门多级审核',
        );
      }
      if ('${v['reason'] ?? ''}'.trim().isEmpty || command.version == null) {
        throw const ApiFailure(FailureKind.validation, '请读取当前版本并填写理由');
      }
      final reviewer = _directManager(session.id);
      final request = Record(
        id: 'org${DateTime.now().microsecondsSinceEpoch}',
        title: '组织配置修改申请',
        ownerId: session.id,
        version: command.version!,
        subtitle: '${stamp(clock())} · 等待直属上级审核',
        fields: {
          'reviewState': '待审',
          'step': 0,
          'approvalMode': 'DIRECT_MANAGER',
          'reviewerId': reviewer?.id,
          'reviewerName': reviewer?.name,
          'reviewerConfigured': reviewer != null,
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
      if (reviewer != null) {
        notify('有新的组织修改申请待审核', 'reviews', request.id, reviewer.id, '审批');
      }
      if (key != null) store.responses[key] = request;
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
    if (previous == null &&
        [
          'approve',
          'reject',
          'receive',
          'feedback',
          'accept',
          'return',
          'archive',
          'withdraw',
          'transfer',
          'reschedule',
        ].contains(action)) {
      throw const ApiFailure(FailureKind.notFound, '记录不存在或无权访问');
    }
    if (resource == 'logs' &&
        !const {
          'submit',
          'save-draft',
          'update-content',
          'update',
        }.contains(action)) {
      throw const ApiFailure(FailureKind.unavailable, '不支持该日志操作，请使用当前日志编辑入口');
    }
    if (resource == 'logs') {
      if (previous != null && previous.ownerId != session.id) {
        throw const ApiFailure(FailureKind.forbidden, '仅作者可修改日志');
      }
      if (previous != null && !LogEditWindow(previous).canEditAt(clock())) {
        throw const ApiFailure(FailureKind.forbidden, '日志提交已满24小时，已锁定');
      }

      if (action == 'update-content' &&
          (previous == null ||
              !isSubmittedDiary(previous) ||
              command.version == null ||
              '${v['work'] ?? v['今日工作'] ?? ''}'.trim().isEmpty)) {
        throw const ApiFailure(FailureKind.validation, '请填写今日工作并读取当前已提交日志版本');
      }
      if (action == 'save-draft' &&
          previous != null &&
          isSubmittedDiary(previous)) {
        throw const ApiFailure(FailureKind.validation, '已提交日志请在首次提交后24小时内直接修改');
      }
      if (action == 'submit' &&
          previous != null &&
          isSubmittedDiary(previous)) {
        throw const ApiFailure(FailureKind.conflict, '日志已经提交，请直接编辑正文');
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
      if (action == 'submit' &&
          !canInitiallySubmitDiaryOn(
            DateTime.parse(businessDate),
            now: clock(),
          )) {
        throw const ApiFailure(FailureKind.validation, '仅可首次提交今天、昨天或前天的日志');
      }
    }
    if (resource == 'organization/profile') {
      if (previous == null || previous.id != session.id || action != 'update') {
        throw const ApiFailure(FailureKind.forbidden, '仅本人可修改个人资料');
      }
      const protectedFields = {
        'name',
        '姓名',
        'departmentId',
        'department_id',
        '部门',
        'position',
        '职位',
        'role',
        '角色',
        'managerId',
        'manager_id',
      };
      if (v.keys.any(protectedFields.contains)) {
        throw const ApiFailure(FailureKind.forbidden, '姓名、组织归属和职位不可自行修改');
      }
      final phone = '${v['手机号'] ?? ''}'.trim();
      final email = '${v['邮箱'] ?? ''}'.trim();
      final age = v['年龄'];
      if (phone.isNotEmpty &&
          !RegExp(r'^\+?[0-9][0-9 ()-]{4,18}[0-9]$').hasMatch(phone)) {
        throw const ApiFailure(FailureKind.validation, '请输入有效电话号码');
      }
      if (email.isNotEmpty &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        throw const ApiFailure(FailureKind.validation, '请输入有效邮箱地址');
      }
      if (age != null && (int.tryParse('$age') ?? -1) < 0) {
        throw const ApiFailure(FailureKind.validation, '年龄必须为非负整数');
      }
      if (phone.isNotEmpty &&
          rows(resource).any(
            (record) =>
                record.id != session.id &&
                '${record.fields['手机号'] ?? record.fields['phone'] ?? ''}'
                        .replaceAll(RegExp(r'\D'), '') ==
                    phone.replaceAll(RegExp(r'\D'), ''),
          )) {
        throw const ApiFailure(FailureKind.conflict, '该电话号码已被其他账号使用');
      }
    }
    if (previous != null &&
        ['dashboard/personal', 'private-notes'].contains(resource) &&
        previous.ownerId != session.id) {
      throw const ApiFailure(FailureKind.forbidden, '仅本人可以修改');
    }
    if (resource == 'dashboard/personal' &&
        action != 'archive' &&
        v['pinned'] == true &&
        previous?.fields['pinned'] != true) {
      final pinnedCount = records
          .where((record) => record.ownerId == session.id)
          .where((record) => record.fields['pinned'] == true)
          .length;
      if (pinnedCount >= 10) {
        throw const ApiFailure(FailureKind.validation, '最多置顶10条个人重点');
      }
    }
    if (previous != null &&
        command.version != null &&
        command.version != previous.version) {
      throw const ApiFailure(FailureKind.conflict, '版本已更新，请返回刷新后重试');
    }
    if (resource == 'reviews' && action != 'request-review') {
      if (previous?.fields['reviewState'] != '待审') {
        throw const ApiFailure(FailureKind.conflict, '该申请已处理或已失效');
      }
      final assignedReviewer = '${previous?.fields['reviewerId'] ?? ''}';
      final currentManager = _directManager(previous!.ownerId);
      if (previous.ownerId == session.id ||
          assignedReviewer.isEmpty ||
          assignedReviewer != session.id ||
          currentManager?.id != session.id) {
        throw const ApiFailure(FailureKind.forbidden, '仅当前配置的直属上级可审核');
      }
      if (command.version == null || command.version != previous.version) {
        throw const ApiFailure(FailureKind.conflict, '申请版本已变化，请重新读取');
      }
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
          !(previous.fields['participantIds'] as List? ?? [previous.ownerId])
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
      final applicant = previous?.ownerId ?? session.id;
      if (session.role == UserRole.founder) {
        if (applicant != session.id) {
          throw const ApiFailure(FailureKind.forbidden, '创始人免审仅适用于本人有权发起的操作');
        }
        final applied = _applyReviewCandidate(
          resource: resource,
          id: id,
          ownerId: applicant,
          candidate: {...v},
          baseVersion: previous?.version,
        );
        final approved = Record(
          id: 'r${clock().microsecondsSinceEpoch}',
          title: '${applied.title} · 修改申请',
          ownerId: session.id,
          version: 1,
          subtitle: '${stamp(clock())} · 系统自动批准',
          fields: {
            'applicantName': session.name,
            'reviewState': '已通过',
            'approvalMode': 'DIRECT_MANAGER',
            'reviewerConfigured': false,
            'decisionSource': 'FOUNDER_EXEMPT',
            'targetResource': resource,
            'targetId': applied.id,
            'baseVersion': previous?.version,
            'effectiveVersion': applied.version,
            'before':
                previous?.fields['body'] ?? previous?.fields['今日工作'] ?? '尚未发布',
            'after': v['内容'] ?? v['今日工作'] ?? '',
            'reason': v['修改理由'] ?? '',
            'reviewEvents': ['系统 · 创始人已获授权操作自动批准并生效'],
          },
        );
        rows('reviews').insert(0, approved);
        notify('创始人授权操作已自动批准', 'reviews', approved.id, session.id, '审核结果');
        if (key != null) store.responses[key] = approved;
        return approved;
      }
      final reviewer = _directManager(applicant);
      final request = Record(
        id: 'r${DateTime.now().microsecondsSinceEpoch}',
        title: '${v['title'] ?? previous?.title ?? '内容'} · 修改申请',
        ownerId: session.id,
        subtitle: '刚刚 · 等待复核',
        fields: {
          'reviewState': '待审',
          'step': 0,
          'approvalMode': 'DIRECT_MANAGER',
          'reviewerId': reviewer?.id,
          'reviewerName': reviewer?.name,
          'reviewerConfigured': reviewer != null,
          'before':
              previous?.fields['body'] ?? previous?.fields['今日工作'] ?? '尚未发布',
          'after': v['内容'] ?? v['今日工作'] ?? '',
          'reason': v['修改理由'] ?? '',
          'targetResource': resource,
          'targetId': id,
          'baseVersion': previous?.version,
          'candidate': v,
          'reviewEvents': <String>[],
        },
      );
      rows('reviews').insert(0, request);
      if (reviewer != null) {
        notify('有新的修改申请待审核', 'reviews', request.id, reviewer.id, '审批');
      }
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
      fields['phase'] = _mockTaskPhase('${fields['status']}');
      fields['dispatcherId'] = previous?.fields['dispatcherId'] ?? session.id;
      if (v.containsKey('tagId') && v['tagId'] != previous?.fields['tagId']) {
        fields.remove('tagName');
      }
      if (v.containsKey('participantIds')) fields.remove('participantNames');
      fields.addAll(_taskDisplayFields(fields));
    }
    if (resource == 'logs') {
      if (action == 'update-content') {
        final work = v['work'] ?? v['今日工作'];
        fields['今日工作'] = work;
        fields['body'] = work;
        fields['versions'] = [
          ...?previous?.fields['versions'] as List?,
          {
            'version': (previous?.version ?? 0) + 1,
            'body': work,
            'time': clock().toUtc().toIso8601String(),
          },
        ];
        for (var i = 0; i < rows('reviews').length; i++) {
          final review = rows('reviews')[i];
          if (review.fields['targetResource'] == 'logs' &&
              review.fields['targetId'] == previous?.id &&
              review.fields['reviewState'] == '待审') {
            rows('reviews')[i] = copy(review, {
              'reviewState': '已失效',
              'reviewEvents': [
                ...?review.fields['reviewEvents'] as List?,
                '日志正文已直接更新，旧修订候选失效',
              ],
            });
          }
        }
      }
      fields['status'] = action == 'save-draft'
          ? '草稿'
          : '已提交';
      fields['submitted'] = fields['status'] == '已提交';
      fields['authorName'] = session.name;
      if (action != 'save-draft') {
        fields['submittedAt'] =
            previous?.fields['submittedAt'] ??
            clock().toUtc().toIso8601String();
      }
      if (action != 'update-content') fields.remove('versions');
      fields.remove('canEdit');
      fields.remove('canWithdraw');
      fields.remove('editableUntil');
    }
    if (resource == 'organization/profile') {
      fields['body'] = v['个人介绍'] ?? previous?.fields['body'] ?? '';
      fields['个人介绍'] = fields['body'];
      if (v.containsKey('手机号')) fields['phone'] = v['手机号'];
      if (v.containsKey('邮箱')) fields['email'] = v['邮箱'];
      if (v.containsKey('性别')) fields['gender'] = v['性别'];
      if (v.containsKey('年龄')) fields['age'] = v['年龄'];
    }
    if (resource == 'notifications') fields['read'] = true;
    if (resource == 'reviews') {
      if (previous?.fields['reviewState'] != '待审') {
        throw const ApiFailure(FailureKind.conflict, '该申请已处理或已失效');
      }
      fields['reviewState'] = action == 'reject' ? '已驳回' : '已通过';
      fields['step'] = action == 'approve' ? 1 : 0;
      fields['reviewEvents'] = [
        ...?previous?.fields['reviewEvents'] as List?,
        '直属上级 · ${session.name} · ${action == 'reject' ? '驳回：${v['reason']}' : '通过'} · ${clock().toString().substring(0, 16)}',
      ];
      if (fields['reviewState'] == '已通过' && fields['candidate'] is Map) {
        final applied = _applyReviewCandidate(
          resource: '${fields['targetResource']}',
          id: '${fields['targetId'] ?? ''}'.isEmpty
              ? null
              : '${fields['targetId']}',
          ownerId: previous!.ownerId,
          candidate: Map<String, dynamic>.from(fields['candidate'] as Map),
          baseVersion: fields['baseVersion'] as int?,
        );
        fields['effectiveVersion'] = applied.version;
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
      title: v['title'] as String? ?? previous?.title ?? '记录',
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
    if (resource == 'organization/profile') {
      final people = rows('organization');
      final personIndex = people.indexWhere((person) => person.id == result.id);
      if (personIndex >= 0) {
        people[personIndex] = copy(people[personIndex], {
          'phone': result.fields['phone'],
          'email': result.fields['email'],
        });
      }
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
