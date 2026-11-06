import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/common/form_page.dart';
import 'package:pandora_mobile/features/dashboard/personnel_page.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/shared/organization_directory.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'support/local_test_state.dart';

const _user = Session(id: 'self', role: UserRole.leader);

Record _person(
  String id,
  String departmentId,
  String teamId, {
  bool known = true,
}) => Record(
  id: id,
  title: id == 'self' ? '林小满' : '同名成员',
  fields: {
    'departmentId': departmentId,
    'departmentName': '产品部',
    'teamId': teamId,
    'teamName': teamId == 'experience' ? '体验组' : '研发组',
    'status': 'ACTIVE',
    'taskSelectable': true,
    if (known) ...{
      'participatingTaskCount': 6,
      'activeTaskCount': 2,
      'todayLogStatus': 'SUBMITTED',
    },
  },
);

class _PeopleRepository extends MockRepository {
  _PeopleRepository(this.people) : super(_user);
  final List<Record> people;
  bool fail = false;
  final resources = <String>[];

  @override
  Future<PageResult> list(String resource, Query query) async {
    resources.add(resource);
    if (resource != 'organization' &&
        resource != 'organization/dispatch-people') {
      return const PageResult([]);
    }
    if (fail) throw const ApiFailure(FailureKind.unavailable, '目录连接失败');
    final visible = people
        .where((p) => PersonOrganization(p).matches(query.search))
        .toList();
    return PageResult(visible, total: visible.length);
  }
}

Future<void> _mount(
  WidgetTester t,
  _PeopleRepository repository, {
  bool picker = false,
  Size size = const Size(390, 1000),
  double scale = 1,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final container = testContainer(
    overrides: [
      sessionProvider.overrideWith((_) => _user),
      repositoryProvider.overrideWithValue(repository),
    ],
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => picker
            ? const Scaffold(
                body: PersonPicker(dispatch: true, multiSelect: true),
              )
            : const PersonnelPage(),
      ),
      GoRoute(
        path: '/me/profile',
        builder: (_, _) => const Scaffold(body: Text('个人资料入口')),
      ),
      GoRoute(
        path: '/me/team/:id',
        builder: (_, state) =>
            Scaffold(body: Text('成员入口 ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    OwnedTestProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _expand(WidgetTester t, {String team = '体验组'}) async {
  await t.tap(find.text('产品部').first);
  await t.pumpAndSettle();
  await t.tap(find.text(team));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'directory groups stable department and team IDs before display names',
    () {
      final a = _person('a', 'department-a', 'same-team');
      final b = _person('b', 'department-b', 'same-team');
      final groups = groupOrganizationPeople([a, b]);
      expect(groups.keys, ['id:department-a', 'id:department-b']);
      expect(
        PersonOrganization(a).branchKey,
        isNot(PersonOrganization(b).branchKey),
      );
      final pathOnly = Record(
        id: 'path',
        title: '成员',
        fields: {
          'organizationPath': [
            {'kind': 'DEPARTMENT', 'id': 'path-department'},
          ],
        },
      );
      expect(PersonOrganization(pathOnly).departmentKey, 'id:path-department');
      expect(PersonOrganization(pathOnly).team, '未分配团队');
    },
  );

  testWidgets(
    'personnel directory expands existing records without changing business badges',
    (t) async {
      final repo = _PeopleRepository([_person('self', 'design', 'experience')]);
      await _mount(t, repo);
      expect(find.byKey(const ValueKey('personnel-record-self')), findsNothing);
      expect(find.byIcon(Icons.folder), findsNothing);
      await _expand(t);
      final record = find.byKey(const ValueKey('personnel-record-self'));
      expect(record, findsOneWidget);
      expect(find.text('参与任务 6'), findsOneWidget);
      expect(find.text('今日日志已提交'), findsOneWidget);
      expect(find.text('未结束任务 2'), findsOneWidget);
      expect(
        t
            .widget<ProtectedAvatar>(
              find.descendant(
                of: record,
                matching: find.byType(ProtectedAvatar),
              ),
            )
            .radius,
        28,
      );
      expect(find.byType(Checkbox), findsNothing);
      await t.tap(find.text('体验组'));
      await t.pumpAndSettle();
      expect(record, findsNothing);
      expect(repo.resources, ['organization']);
    },
  );

  testWidgets(
    'team search expands the full path and preserves unknown statistics',
    (t) async {
      await _mount(
        t,
        _PeopleRepository([
          _person('self', 'design', 'experience'),
          _person('unknown', 'design', 'engineering', known: false),
        ]),
      );
      await t.enterText(find.byType(TextField), '研发组');
      await t.pumpAndSettle();
      expect(find.widgetWithText(ListTile, '研发组'), findsOneWidget);
      expect(find.text('同名成员'), findsOneWidget);
      expect(find.text('参与任务数未知'), findsOneWidget);
      expect(find.text('今日日志状态未知'), findsOneWidget);
      expect(find.text('任务状态未知'), findsOneWidget);
      expect(find.byKey(const ValueKey('personnel-record-self')), findsNothing);
      await t.enterText(find.byType(TextField), '不存在的人员');
      await t.pumpAndSettle();
      expect(find.text('暂无匹配人员'), findsOneWidget);
      // Repeating a previous query after an empty result must reopen its path.
      await t.enterText(find.byType(TextField), '研发组');
      await t.pumpAndSettle();
      expect(find.text('同名成员'), findsOneWidget);
      await t.enterText(find.byType(TextField), '');
      await t.pumpAndSettle();
      expect(find.text('产品部').first, findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'personnel failure is retryable rather than reported as an empty organization',
    (t) async {
      final repo = _PeopleRepository([_person('self', 'design', 'experience')])
        ..fail = true;
      await _mount(t, repo);
      expect(find.text('暂时无法连接'), findsOneWidget);
      expect(find.text('暂无匹配人员'), findsNothing);
      repo.fail = false;
      await t.tap(find.text('重新加载'));
      await t.pumpAndSettle();
      await _expand(t);
      expect(find.text('参与任务 6'), findsOneWidget);
      expect(repo.resources.where((r) => r == 'organization').length, 2);
    },
  );

  testWidgets(
    'personnel records retain own-profile navigation at 320dp and large text',
    (t) async {
      await _mount(
        t,
        _PeopleRepository([_person('self', 'design', 'experience')]),
        size: const Size(320, 900),
        scale: 1.5,
      );
      await _expand(t);
      final record = find.byKey(const ValueKey('personnel-record-self'));
      await t.ensureVisible(record);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.text('林小满'));
      await t.pumpAndSettle();
      expect(find.text('个人资料入口'), findsOneWidget);
    },
  );

  testWidgets(
    'picker places the protected avatar before the name and retains selected management',
    (t) async {
      await _mount(
        t,
        _PeopleRepository([_person('self', 'design', 'experience')]),
        picker: true,
        size: const Size(320, 640),
        scale: 1.5,
      );
      await _expand(t);
      final row = find.byKey(const ValueKey('picker-person-self'));
      final tile = t.widget<ListTile>(row);
      expect(tile.leading, isA<ProtectedAvatar>());
      expect(tile.trailing, isA<Checkbox>());
      final avatar = find.descendant(
        of: row,
        matching: find.byType(ProtectedAvatar),
      );
      final name = find.descendant(of: row, matching: find.text('林小满'));
      expect(t.getCenter(avatar).dx, lessThan(t.getCenter(name).dx));
      await t.tap(row);
      await t.pumpAndSettle();
      expect(t.widget<ListTile>(row).selected, isTrue);
      expect(
        find.byKey(const ValueKey('picker-selected-self')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('person-picker-confirm')).hitTestable(),
        findsOneWidget,
      );
      await t.tap(find.text('清空'));
      await t.pumpAndSettle();
      expect(t.widget<ListTile>(row).selected, isFalse);
      expect(t.takeException(), isNull);
    },
  );
}
