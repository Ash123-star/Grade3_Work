import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/tenure.dart';

void main() {
  final today = DateTime(2026, 11, 1);
  test('missing or future start date is not guessed', () {
    expect(tenureLabel(null, today), '未提供');
    expect(tenureLabel(DateTime(2026, 11, 2), today), '未提供');
    expect(employmentDateLabel(null), '未提供');
    expect(employmentDateLabel('not-a-date'), '未提供');
    expect(employmentDateLabel('2026-02-31'), '未提供');
  });
  test('short tenure and month boundaries', () {
    expect(tenureLabel(DateTime(2026, 11, 1), today), '0年0个月0天');
    expect(tenureLabel(DateTime(2026, 10, 3), today), '0年0个月29天');
    expect(tenureLabel(DateTime(2026, 10, 1), today), '0年1个月0天');
    expect(
      tenureLabel(DateTime(2026, 1, 31), DateTime(2026, 2, 28)),
      '0年1个月0天',
    );
    expect(tenureLabel(DateTime(2025, 12, 2), today), '0年10个月30天');
  });
  test('days after clamped anniversary and UTC civil dates', () {
    expect(tenureLabel(DateTime(2026, 1, 31), DateTime(2026, 3, 1)), '0年1个月1天');
    expect(tenureLabel(DateTime(2024, 2, 29), DateTime(2025, 3, 1)), '1年0个月1天');
    expect(
      tenureLabel(DateTime.utc(2026, 10, 31, 23), DateTime.utc(2026, 11, 2)),
      '0年0个月2天',
    );
  });
  test('years and months', () {
    expect(tenureLabel(DateTime(2025, 11, 1), today), '1年0个月0天');
    expect(tenureLabel(DateTime(2025, 8, 1), today), '1年3个月0天');
    expect(
      tenureLabel(DateTime(2024, 2, 29), DateTime(2025, 2, 28)),
      '1年0个月0天',
    );
    expect(tenureLabel(DateTime(2020, 5, 18), today), '6年5个月14天');
    expect(employmentDateLabel('2026-05-18'), '2026-05-18');
  });
}
