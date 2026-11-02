import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';

/// Stable records for workflow tests; independent of the rotating demo catalog.
DemoStore workflowFixture() => DemoStore()
  ..records.addAll({
    'organization': [
      const Record(
        id: 'u1',
        title: '林小满',
        fields: {'departmentName': '产品部', 'department_id': 'product'},
      ),
      const Record(
        id: 'u2',
        title: '陈一诺',
        fields: {
          'managerId': 'u1',
          'departmentName': '产品部',
          'department_id': 'product',
        },
      ),
      const Record(
        id: 'u3',
        title: '许知远',
        fields: {
          'managerId': 'u1',
          'departmentName': '技术部',
          'department_id': 'tech',
        },
      ),
    ],
    'logs': [
      Record(
        id: '7',
        title: '锁定日志',
        ownerId: 'u1',
        fields: {
          'status': '已提交',
          '今日工作': '保留历史内容',
          'businessDate': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String()
              .split('T')
              .first,
          'submittedAt': DateTime.now()
              .subtract(const Duration(hours: 25))
              .toUtc()
              .toIso8601String(),
        },
      ),
      for (var i = 1; i <= 3; i++)
        Record(
          id: '$i',
          title: '日报$i',
          ownerId: 'u$i',
          fields: {
            'status': '已提交',
            'submittedAt': DateTime.now().toUtc().toIso8601String(),
            'businessDate': DateTime.now().toIso8601String().split('T').first,
            '今日工作': '已完成验收记录$i',
            'authorName': ['林小满', '陈一诺', '许知远'][i - 1],
            'departmentName': i == 3 ? '技术部' : '产品部',
            'departmentId': i == 3 ? 'tech' : 'product',
            'comments': <Map<String, dynamic>>[],
          },
        ),
    ],
    'tasks': [
      const Record(
        id: '1',
        title: '验收任务',
        ownerId: 'u1',
        fields: {
          'status': '待接收',
          'dispatcherId': 'u1',
          'participantIds': ['u1'],
          '任务内容': '核对交付',
          'deadline': '2027-10-21T18:00:00+08:00',
        },
      ),
    ],
    'reviews': [
      const Record(
        id: '1',
        title: '独立复核',
        ownerId: 'u2',
        fields: {
          'reviewState': '待审',
          'step': 0,
          'approvalMode': 'DIRECT_MANAGER',
          'reviewerId': 'u1',
          'reviewerName': '林小满',
          'reviewerConfigured': true,
          'applicantName': '陈一诺',
          'before': '原文',
          'after': '修订',
          'candidateVersion': 2,
          'baseVersion': 1,
          'reason': '补充说明',
        },
      ),
      const Record(
        id: '2',
        title: '本人申请',
        ownerId: 'u1',
        fields: {'reviewState': '待审', 'step': 0},
      ),
    ],
    'dashboard/company': [
      const Record(
        id: '1',
        title: '公司重点',
        ownerId: 'u1',
        fields: {'body': '季度交付'},
      ),
    ],
    'dashboard/personal': [
      const Record(
        id: '1',
        title: '梳理工作台体验',
        ownerId: 'u1',
        fields: {'body': '核对交互'},
      ),
    ],
    'ai-maps': [
      const Record(
        id: '1',
        title: '确认交互稿中的关键依赖',
        ownerId: 'u1',
        fields: {'任务内容': '核对接口与交互依赖', 'body': '核对接口与交互依赖'},
      ),
    ],
  });
