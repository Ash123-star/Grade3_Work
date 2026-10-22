import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:dio/dio.dart';
import 'package:pandora_mobile/data/models/attachments.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/log_edit_window.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

enum DemoScenario { normal, empty, offline, forbidden }

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
    this.dispatch = false,
    this.companyReviewer = false,
  });

  final String id, name, departmentId, departmentName, teamId, teamName;
  final String managerId, intro;
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
    if (resource == 'feedback') return [];
    if (resource == 'tasks') return _seedTasks(now, instant);
    if (resource == 'logs') return _seedLogs(now, instant);
    if (resource == 'dashboard/personal') return _seedPersonalFocus(now);
    if (resource == 'reviews') return _seedReviews(now);
    if (resource == 'notifications') return _seedNotifications(now);
    if (resource == 'audit') return _seedAudit(now);
    if (resource == 'organization/admin') return _seedDepartments();
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
      '完成需求边界与验收口径确认',
      '整理访谈发现并回访关键用户',
      '完成接口分页与权限校验联调',
      '补齐移动端关键页面交互细节',
      '复核自动化回归和发布阻断项',
      '整理本周渠道内容与排期',
      '跟进重点客户部署问题闭环',
      '梳理服务稳定性告警与容量计划',
      '更新部门目标和资源风险清单',
      '复核客户成功交付里程碑',
      '完成体验评审问题分级',
      '协调跨部门版本依赖与回滚方案',
      '分析内容渠道转化并提出实验',
      '更新组织账号与权限复核记录',
      '完善质量检查清单和缺陷复现步骤',
      '准备经营例会数据和重点决策项',
      '制定用户增长实验的停止条件',
      '归档交付培训材料和客户反馈',
      '整理用户研究原始记录与结论',
    ];
    return [
      for (final (i, account) in demoAccounts.indexed)
        for (var slot = 0; slot < 2; slot++)
          Record(
            id: 'focus-${account.id}-${slot + 1}',
            title: slot == 0
                ? focus[i % focus.length]
                : '${account.teamName} · ${focus[(i + 7) % focus.length]}',
            ownerId: account.id,
            subtitle: '${account.departmentName} · ${account.teamName}',
            fields: {
              'body':
                  '${account.intro} 本阶段同步跟进：${focus[(i + slot + 3) % focus.length]}。',
              'status': slot == 0 ? '进行中' : '待复核',
              '排序位置': slot,
              'createdAt': now
                  .subtract(Duration(days: slot + i % 4))
                  .toIso8601String(),
              'departmentName': account.departmentName,
              'teamName': account.teamName,
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
              'startAt': _atDay(start, 9 + i % 3).toIso8601String(),
              'endAt': _atDay(start, 12 + i % 3).toIso8601String(),
              'deadline': deadline.toIso8601String(),
              'createdAt': instant
                  .subtract(Duration(days: i % 12 + 1))
                  .toUtc()
                  .toIso8601String(),
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
          final approver = _account(
            applicant.managerId.isEmpty ? 'u-founder' : applicant.managerId,
          );
          final pending = i % 3 == 0;
          return Record(
            id: 'review-demo-${i + 1}',
            title: subject,
            ownerId: applicant.id,
            subtitle:
                '${applicant.name} · ${applicant.departmentName} · ${stamp(now.subtract(Duration(days: i)))}',
            fields: {
              'applicantName': applicant.name,
              'reviewerName': approver.name,
              'reviewState': pending
                  ? '待审'
                  : i % 2 == 0
                  ? '已通过'
                  : '已驳回',
              'targetResource': i % 2 == 0 ? 'tasks' : 'logs',
              'targetId': i % 2 == 0
                  ? 'task-demo-${i + 1}'
                  : 'log-${applicant.id}-1',
              'reason':
                  '${applicant.name}说明了业务背景、影响范围和期望生效时间，等待${approver.name}核对。',
              'before': '当前已生效内容保持不变。',
              'after': '按申请补充交付范围、记录或组织说明。',
              'step': 0,
              'createdAt': now.subtract(Duration(days: i)).toIso8601String(),
              'reviewEvents': [
                '${applicant.name}提交申请',
                if (!pending) '${approver.name}${i % 2 == 0 ? '通过' : '要求补充说明'}',
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
          'canWithdraw':
              item.ownerId == session.id &&
              isSubmittedDiary(item) &&
              LogEditWindow(item).canEditAt(clock()),
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
      if (previous != null && !LogEditWindow(previous).canEditAt(clock())) {
        throw const ApiFailure(FailureKind.forbidden, '日志提交已满24小时，已锁定');
      }

      if (action == 'update') {
        throw const ApiFailure(FailureKind.validation, '已提交日志请申请修订');
      }
      if (action == 'withdraw' || action == 'request-review') {
        if (previous == null || !isSubmittedDiary(previous)) {
          throw const ApiFailure(FailureKind.validation, '请先提交日志');
        }
        if (command.version == null ||
            '${v['reason'] ?? v['修改理由'] ?? ''}'.trim().isEmpty) {
          throw const ApiFailure(FailureKind.validation, '请填写原因并提供当前版本');
        }
      }
      if (action == 'save-draft' &&
          previous != null &&
          isSubmittedDiary(previous)) {
        throw const ApiFailure(FailureKind.validation, '已提交日志请申请修订');
      }
      if (action == 'submit' &&
          previous != null &&
          isSubmittedDiary(previous)) {
        throw const ApiFailure(FailureKind.conflict, '日志已经提交，请申请修订');
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
          'baseVersion': previous?.version,
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
      fields['status'] = ['save-draft', 'withdraw'].contains(action)
          ? '草稿'
          : '已提交';
      fields['submitted'] = fields['status'] == '已提交';
      fields['authorName'] = session.name;
      if (action != 'save-draft') {
        fields['submittedAt'] =
            previous?.fields['submittedAt'] ??
            clock().toUtc().toIso8601String();
      }
      fields.remove('versions');
      fields.remove('canEdit');
      fields.remove('canWithdraw');
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
        if (fields['baseVersion'] != null &&
            (pos < 0 || target[pos].version != fields['baseVersion'])) {
          throw const ApiFailure(FailureKind.conflict, '原记录已更新，请重新申请');
        }
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
