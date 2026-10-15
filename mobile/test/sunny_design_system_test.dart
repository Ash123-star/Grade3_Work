import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'support/local_test_state.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/shared/sunny_button.dart';
import 'package:pandora_mobile/shared/sunny_widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/page_states.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/shared/widgets.dart' show notice;
import 'package:pandora_mobile/core/errors/api_failure.dart';

Widget host(Widget child, {bool reduceMotion = false, double scale = 1}) =>
    MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  test('semantic roles interpolate colors, geometry and motion', () {
    final theme = appTheme(), original = theme.extension<SunnyPaperTokens>()!;
    final other = original.copyWith(
      canvas: Colors.black,
      buttonRadius: 26,
      pressDuration: const Duration(milliseconds: 300),
    );
    final halfway = original.lerp(other, .5);
    expect(halfway.canvas, Color.lerp(original.canvas, Colors.black, .5));
    expect(halfway.buttonRadius, 22);
    expect(halfway.pressDuration.inMilliseconds, 200);
    expect(theme.colorScheme.onPrimaryContainer, const Color(0xFF246447));
    expect(theme.colorScheme.secondaryContainer, original.ai);
    expect(theme.colorScheme.tertiaryContainer, original.success);
    expect(
      theme.navigationBarTheme.iconTheme!.resolve({
        WidgetState.selected,
      })!.color,
      const Color(0xFF319E7A),
    );
  });

  testWidgets('press edge, keyboard focus and disabled activation', (t) async {
    var calls = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Widget button(VoidCallback? action) => SizedBox(
      width: 220,
      child: SunnyPrimaryButton(
        focusNode: focus,
        onPressed: action,
        child: const Text('提交日志'),
      ),
    );
    await t.pumpWidget(host(button(() => calls++)));
    final surface = find.descendant(
      of: find.byType(SunnyPrimaryButton),
      matching: find.byType(AnimatedContainer),
    );
    BoxDecoration decoration() =>
        t.widget<AnimatedContainer>(surface).decoration! as BoxDecoration;
    expect(decoration().boxShadow!.first.offset.dy, 3);
    final finger = await t.startGesture(t.getCenter(find.byType(FilledButton)));
    await t.pump(const Duration(milliseconds: 120));
    expect(decoration().boxShadow!.first.offset.dy, 1);
    await finger.up();
    await t.pumpAndSettle();
    expect(calls, 1);
    focus.requestFocus();
    await t.pumpAndSettle();
    expect(decoration().boxShadow!.any((s) => s.spreadRadius == 3), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(calls, 2);
    await t.pumpWidget(host(button(null)));
    await t.pumpAndSettle();
    await t.tap(find.byType(FilledButton));
    expect(calls, 2);
    expect(decoration().boxShadow!.any((s) => s.offset.dy > 0), isFalse);
    final style = t.widget<FilledButton>(find.byType(FilledButton)).style!;
    expect(
      style.backgroundColor!.resolve({WidgetState.disabled}),
      const SunnyPaperTokens().disabled,
    );
  });

  testWidgets('busy action keeps label and width and does not activate', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    var calls = 0;
    Widget button(bool busy) => SunnyPrimaryButton(
      loading: busy,
      onPressed: () => calls++,
      child: const Text('保存建议草稿'),
    );
    await t.pumpWidget(host(button(false)));
    final size = t.getSize(find.byType(SunnyPrimaryButton));
    await t.pumpWidget(host(button(true)));
    await t.pump();
    expect(t.getSize(find.byType(SunnyPrimaryButton)), size);
    expect(find.text('保存建议草稿'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.tap(find.byType(FilledButton));
    expect(calls, 0);
    expect(
      t
          .getSemantics(find.byType(FilledButton))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('reduced motion changes pressed state without animation', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        SunnyPrimaryButton(onPressed: () {}, child: const Text('确认')),
        reduceMotion: true,
      ),
    );
    final finger = await t.startGesture(t.getCenter(find.byType(FilledButton)));
    await t.pump();
    final surface = t.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect(surface.duration, Duration.zero);
    expect(surface.transform!.getTranslation().y, 2);
    await finger.up();
    await t.pump();
  });

  testWidgets('empty, offline and permission use truthful separate states', (
    t,
  ) async {
    await t.pumpWidget(host(const EmptyIllustration()));
    expect(
      t.widget<TuantuanMascot>(find.byType(TuantuanMascot)).pose,
      'empty',
    );
    await t.pumpWidget(
      host(
        RecordFailure(
          const ApiFailure(FailureKind.timeout, '网络连接超时'),
          retry: () {},
        ),
      ),
    );
    expect(
      t.widget<TuantuanMascot>(find.byType(TuantuanMascot)).pose,
      'error',
    );
    await t.pumpWidget(
      host(
        const EmptyIllustration(
          title: '无权访问',
          subtitle: '请返回本人面板',
          showCharacter: false,
        ),
      ),
    );
    expect(find.byType(TuantuanMascot), findsNothing);
    expect(find.text('无权访问'), findsOneWidget);
  });

  testWidgets('only confirmed success feedback uses success pose', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      host(
        Builder(
          builder: (c) {
            context = c;
            return const Text('已保存后的反馈入口');
          },
        ),
      ),
    );
    notice(context, '草稿已加密保存到此设备', success: true);
    await t.pump();
    expect(
      t.widget<TuantuanMascot>(find.byType(TuantuanMascot)).pose,
      'success',
    );
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    await t.pump();
    notice(context, '修订已提交，等待复核');
    await t.pump();
    expect(find.byType(TuantuanMascot), findsNothing);
  });

  testWidgets('calendar type toggles expose changed accessibility state', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final c = testContainer(
      overrides: [
        repositoryProvider.overrideWithValue(MockRepository(const Session())),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: host(const SingleChildScrollView(child: CalendarContent())),
      ),
    );
    await t.pumpAndSettle();
    Semantics filter() => t
        .widgetList<Semantics>(find.byType(Semantics))
        .firstWhere((w) => w.properties.toggled != null);
    expect(filter().properties.toggled, isTrue);
    await t.tap(find.text('● 任务'));
    await t.pumpAndSettle();
    expect(filter().properties.toggled, isFalse);
    expect(find.text('○ 任务'), findsOneWidget);
    expect(t.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('render component states and all six original poses', (t) async {
    final font = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
          ),
        ),
      );
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await font.load();
    await icons.load();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    Future<void> capture(String name) async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final bitmap = await render.toImage(pixelRatio: 1);
        final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        final output = File('docs/evidence/stage3-rebuild/$name.png');
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes!.buffer.asUint8List());
        bitmap.dispose();
      });
    }

    for (final scale in [1.0, 1.5]) {
      await t.pumpWidget(
        host(
          RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: SunnyPalette.paper,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '阳光纸张 · 动漫橙',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final pair in [
                      [
                        BuddyPose.welcome,
                        BuddyPose.writing,
                        BuddyPose.explaining,
                      ],
                      [BuddyPose.success, BuddyPose.empty, BuddyPose.retry],
                    ])
                      Row(
                        children: [
                          for (final pose in pair)
                            Expanded(
                              child: Column(
                                children: [
                                  WorkBuddy(size: 48, pose: pose),
                                  Text(
                                    pose.name,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    SunnyPrimaryButton(
                      onPressed: () {},
                      child: const Text('提交日志'),
                    ),
                    const SizedBox(height: 12),
                    const SunnyPrimaryButton(
                      onPressed: null,
                      child: Text('无派发权限'),
                    ),
                    const SizedBox(height: 12),
                    SunnyPrimaryButton(
                      onPressed: () {},
                      loading: true,
                      child: const Text('保存建议草稿'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          scale: scale,
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull);
      await capture(
        scale == 1 ? '41-sunny-component-states' : '42-sunny-states-large-text',
      );
    }
    await t.pumpWidget(
      host(
        RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: SunnyPalette.paper,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SunnyWelcome(
                    title: '先核对来源',
                    subtitle: '建议需人工确认',
                    pose: BuddyPose.explaining,
                  ),
                  const SizedBox(height: 16),
                  const TextField(
                    decoration: InputDecoration(
                      labelText: '今日工作',
                      errorText: '请填写今日工作',
                    ),
                  ),
                  const SizedBox(height: 16),
                  PillTabs(
                    labels: const ['日', '周', '月'],
                    selected: 1,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 16),
                  const PaperSurface(child: Text('候选已提交 · 等待独立复核')),
                  const SizedBox(height: 16),
                  const ErrorPanel('提交失败，内容仍在编辑器中'),
                ],
              ),
            ),
          ),
        ),
        scale: 1.5,
      ),
    );
    await t.pump();
    expect(t.takeException(), isNull);
    await capture('43-sunny-field-and-state');
    await t.pumpWidget(const SizedBox.shrink());
  });
}
