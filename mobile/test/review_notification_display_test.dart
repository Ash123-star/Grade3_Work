import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/review_display.dart';
import 'package:pandora_mobile/data/models/notification_display.dart';

void main() {
  test('通知保留业务标题，只本地化空白和协议代码', () {
    expect(notificationDisplayTitle('客户验收提醒', 'TASK_ASSIGNED'), '客户验收提醒');
    expect(
      notificationDisplayTitle('TASK_DISPATCHED', 'TASK_DISPATCHED'),
      '收到新任务',
    );
    expect(notificationDisplayTitle('', 'UNKNOWN'), '工作通知');
    expect(notificationResource('REVIEW_PENDING'), 'reviews');
    expect(notificationResource('UNKNOWN'), isNull);
  });
  test('审核快照展示业务字段与授权引用，隐藏内部元数据', () {
    final result = reviewSnapshotText(
      {
        'title': '门店验收',
        'participantIds': ['u1', 'u2'],
        'status': 'ACTIVE',
        'version': 8,
        'id': 'internal-id',
        'deadline': '2026-10-30T01:30:00Z',
        'attachments': ['a', 'b'],
      },
      {
        'people': {'u1': '周启航'},
      },
    );
    expect(result, contains('标题：门店验收'));
    expect(result, contains('参与人：周启航、名称暂不可用'));
    expect(result, contains('截止时间：2026年10月30日 09:30'));
    expect(result, contains('附件：2 个附件'));
    expect(result, isNot(contains('internal-id')));
    expect(result, isNot(contains('version')));
    expect(result, isNot(contains('u2')));
  });
}
