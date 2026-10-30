import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/record_display.dart';

void main() {
  test('日志标题使用正文摘要而非日期，去序号并处理空正文', () {
    expect(workLogTitle({'businessDate': '2026-10-30', 'work': '\n1. 核对退款数据\n2. 更新接口'}), '核对退款数据');
    expect(workLogTitle({'work': '   \n\t'}), '工作日志');
    expect(workLogTitle({'work': '正文'}, explicitTitle: '交付复盘'), '交付复盘');
    final title = workLogTitle({'work': List.filled(60, '🚀').join()});
    expect(title.runes.length, 49);
    expect(title.endsWith('…'), isTrue);
  });

  test('姓名缺失时不使用账户或人员ID兜底', () {
    expect(displayPersonName(' 周启航 '), '周启航');
    expect(displayPersonName(null), '未知成员');
    expect(displayPersonName(' '), '未知成员');
  });
}
