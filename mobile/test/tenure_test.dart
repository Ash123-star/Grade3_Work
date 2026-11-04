import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/tenure.dart';

void main() {
  final today = DateTime(2026, 11, 1);
  test('missing or future start date is not guessed', () {
    expect(tenureLabel(null, today), '未提供');
    expect(tenureLabel(DateTime(2026, 11, 2), today), '未提供');
    expect(employmentDateLabel(null), '未提供');
    expect(employmentDateLabel('not-a-date'), '未提供');
  });
  test('short tenure and month boundaries', () {
    expect(tenureLabel(DateTime(2026, 11, 1), today), '不满1个月');
    expect(tenureLabel(DateTime(2026, 10, 3), today), '不满1个月');
    expect(tenureLabel(DateTime(2026, 10, 1), today), '1个月');
    expect(tenureLabel(DateTime(2026, 1, 31), DateTime(2026, 2, 28)), '1个月');
    expect(tenureLabel(DateTime(2025, 12, 2), today), '10个月');
  });
  test('years and months', () {
    expect(tenureLabel(DateTime(2025, 11, 1), today), '1年');
    expect(tenureLabel(DateTime(2025, 8, 1), today), '1年3个月');
    expect(tenureLabel(DateTime(2024, 2, 29), DateTime(2025, 2, 28)), '1年');
    expect(tenureLabel(DateTime(2020, 5, 18), today), '6年5个月');
    expect(employmentDateLabel('2026-05-18'), '2026-05-18');
  });
}
