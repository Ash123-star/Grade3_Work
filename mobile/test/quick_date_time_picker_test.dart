import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';
import 'package:pandora_mobile/shared/quick_date_time_picker.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

void main() {
  Future<void> mount(
    WidgetTester t,
    Future<void> Function(BuildContext) open, {
    double width = 390,
    double scale = 1,
  }) async {
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => open(context),
                child: const Text('选择'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('选择'));
    await t.pumpAndSettle();
  }

  testWidgets('date accepts a grid tap immediately and clamps initial bounds', (
    t,
  ) async {
    DateTime? value;
    await mount(
      t,
      (c) async => value = await showPremiumDatePicker(
        c,
        initial: DateTime(1900),
        firstDate: DateTime(2024, 2, 10),
        lastDate: DateTime(2024, 2, 29),
      ),
    );
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(QuickDateTimePicker), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('quick-day:2024-2-9')));
    await t.pumpAndSettle();
    expect(value, isNull);
    await t.tap(find.byKey(const ValueKey('quick-day:2024-2-29')));
    await t.pumpAndSettle();
    expect(value, DateTime(2024, 2, 29));
    expect(find.byType(QuickDateTimePicker), findsNothing);
  });

  testWidgets('same panel validates leap dates and preserves exact minutes', (
    t,
  ) async {
    DateTime? value;
    await mount(
      t,
      (c) async => value = await showPremiumDateTimePicker(
        c,
        initial: DateTime(2024, 2, 29, 9, 37),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100, 12, 31),
      ),
    );
    expect(find.byKey(const ValueKey('quick-date-时')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('quick-date-年')), '2025');
    await t.tap(find.byKey(const ValueKey('quick-date-confirm')));
    await t.pumpAndSettle();
    expect(value, isNull);
    expect(find.text('请输入有效的年、月、日'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('quick-date-日')), '28');
    await t.tap(find.byKey(const ValueKey('quick-date-confirm')));
    await t.pumpAndSettle();
    expect(value, DateTime(2025, 2, 28, 9, 37));
    expect(find.byType(QuickDateTimePicker), findsNothing);
  });

  testWidgets('time rejects invalid values and cancellation does not commit', (
    t,
  ) async {
    TimeOfDay? value;
    await mount(
      t,
      (c) async => value = await showPremiumTimePicker(
        c,
        initial: const TimeOfDay(hour: 18, minute: 17),
      ),
    );
    expect(find.byKey(const ValueKey('quick-date-年')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('quick-date-时')), '24');
    await t.tap(find.byKey(const ValueKey('quick-date-confirm')));
    await t.pumpAndSettle();
    expect(find.text('小时范围 0–23，分钟范围 0–59'), findsOneWidget);
    await t.tap(find.byTooltip('取消选择'));
    await t.pumpAndSettle();
    expect(value, isNull);
  });

  testWidgets(
    'small screen and large text keep fields and confirmation usable',
    (t) async {
      DateTime? value;
      await mount(
        t,
        (c) async => value = await showPremiumDateTimePicker(
          c,
          initial: DateTime(2026, 11, 17, 18),
        ),
        width: 320,
        scale: 1.6,
      );
      await t.ensureVisible(find.byKey(const ValueKey('quick-date-confirm')));
      await t.tap(find.byKey(const ValueKey('quick-date-confirm')));
      await t.pumpAndSettle();
      expect(value, DateTime(2026, 11, 17, 18));
      expect(t.takeException(), isNull);
    },
  );
}
