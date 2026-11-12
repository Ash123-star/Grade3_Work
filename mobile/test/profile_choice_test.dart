import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/dashboard/own_profile_page.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

class ProfileRepository implements Repository {
  Record profile = Record(
    id: 'u1',
    title: '员工',
    version: 1,
    fields: {'gender': '历史任意输入'},
  );
  Command? saved;
  final limits = <String, int>{};
  @override
  Future<Record> detail(String resource, String id, {String? ownerId}) async =>
      profile;
  @override
  Future<Record> execute(String resource, Command command) async {
    saved = command;
    profile = Record(
      id: 'u1',
      title: '员工',
      version: profile.version + 1,
      fields: {'gender': command.values['性别']},
    );
    return profile;
  }

  @override
  Future<PageResult> list(String resource, Query query) async {
    limits[resource] = query.limit;
    return PageResult([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('home preview requests three tasks and two company items', () async {
    final repository = ProfileRepository();
    final container = ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        sessionProvider.overrideWith((ref) => const Session()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(homePreviewProvider('tasks/received-card').future);
    await container.read(homePreviewProvider('dashboard/company').future);
    expect(repository.limits, {
      'tasks/received-card': 3,
      'dashboard/company': 2,
    });
  });
  testWidgets('gender is a choice, cancels edits and saves selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = ProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          sessionProvider.overrideWith((ref) => const Session()),
        ],
        child: MaterialApp(theme: appTheme(), home: const OwnProfilePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('历史任意输入'), findsNothing);
    await tester.tap(find.byTooltip('编辑个人资料'));
    await tester.pumpAndSettle();
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('女').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.saved, isNull);
    await tester.tap(find.byTooltip('编辑个人资料'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(dropdown);
    expect(
      tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue,
      isNull,
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('男').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repository.saved?.values['性别'], '男');
    expect(repository.saved?.version, 1);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('男'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
