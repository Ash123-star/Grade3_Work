import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/push/push_controller.dart';
import 'package:pandora_mobile/core/push/push_platform.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/settings/push_settings_page.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

class TestPushPlatform implements PushPlatform {
  bool available = true, permission = true, requestAllowed = true;
  int initializations = 0, clears = 0;
  Map<String, dynamic>? click;
  void Function()? callback;
  @override
  bool get supported => true;
  @override
  Future<bool> configured() async => available;
  @override
  Future<bool> permitted() async => permission;
  @override
  Future<bool> requestPermission() async => permission = requestAllowed;
  @override
  Future<String> initialize() async {
    initializations++;
    return 'device-12345678';
  }

  @override
  Future<void> clear({bool discardOpen = false}) async {
    clears++;
    if (discardOpen) click = null;
  }

  @override
  Future<Map<String, dynamic>?> drainOpen() async {
    final c = click;
    click = null;
    return c;
  }

  @override
  Future<void> settings() async {}
  @override
  void onOpen(void Function() callback) {
    this.callback = callback;
  }
}

class TestPushApi implements PushApi {
  TestPushApi(this.owner);
  final String owner;
  PushPreferences p = const PushPreferences(configured: true, enabled: true);
  int binds = 0, unbinds = 0, saves = 0, opens = 0;
  bool failSave = false;
  Completer<void>? bindWait;
  Map result = {
    'resource': 'tasks',
    'objectId': '11111111-1111-1111-1111-111111111111',
  };
  @override
  Future<PushPreferences> preferences() async => p;
  @override
  Future<PushPreferences> save(Map<String, dynamic> body) async {
    saves++;
    if (failSave) throw StateError('conflict');
    p = PushPreferences.fromJson({
      ...body,
      'configured': true,
      'version': p.version + 1,
    });
    return p;
  }

  @override
  Future<String> bind(String device) async {
    binds++;
    await bindWait?.future;
    return 'lease-$owner';
  }

  @override
  Future<void> unbind(String device) async {
    unbinds++;
  }

  @override
  Future<Map> open(String id, String device, String binding) async {
    opens++;
    return result;
  }

  @override
  Future<Map> membership(String id) async => {
    'status': 'REJECTED',
    'steps': [
      {'reason': '部门信息需补充'},
    ],
  };
  @override
  void close() {}
}

void main() {
  const a = Session(id: 'a', token: 'token-a');
  const b = Session(id: 'b', token: 'token-b');
  late TestPushPlatform platform;
  late Map<String, TestPushApi> apis;
  late PushController controller;
  late List<String> routes;
  setUp(() {
    platform = TestPushPlatform();
    apis = {};
    routes = [];
    controller = PushController(
      platform,
      (token) => apis.putIfAbsent(token, () => TestPushApi(token)),
      routes.add,
    );
  });
  tearDown(() {
    if (controller.mounted) controller.dispose();
  });
  test(
    'cold click waits for binding and uses authorized destination',
    () async {
      platform.click = {'notificationId': 'n', 'binding': 'lease-token-a'};
      await controller.sync(a);
      expect(routes, ['/item/tasks/11111111-1111-1111-1111-111111111111']);
      expect(apis['token-a']!.opens, 1);
      expect(controller.state.permitted, isTrue);
    },
  );
  test(
    'old account click discarded after switching and old device unbound',
    () async {
      await controller.sync(a);
      platform.click = {'notificationId': 'old', 'binding': 'lease-token-a'};
      await controller.sync(b);
      expect(apis['token-a']!.unbinds, 1);
      expect(apis['token-b']!.opens, 0);
      expect(routes, isEmpty);
    },
  );
  test('logout unbinds and clears system notifications', () async {
    await controller.sync(a);
    await controller.sync(const Session(active: false));
    expect(apis['token-a']!.unbinds, 1);
    expect(platform.clears, greaterThan(0));
    expect(controller.state.preferences.enabled, isFalse);
  });
  test('late old binding is released before a new account can bind', () async {
    final old = apis['token-a'] = TestPushApi('token-a')
      ..bindWait = Completer<void>();
    final first = controller.sync(a);
    while (old.binds == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = controller.sync(b);
    old.bindWait!.complete();
    await Future.wait([first, second]);
    expect(old.unbinds, 1);
    expect(apis['token-b']!.binds, 1);
    expect(apis['token-b']!.unbinds, 0);
    expect(controller.binding, 'lease-token-b');
  });
  test(
    'same-account refresh preserves the click lease during registration',
    () async {
      final current = apis['token-a'] = TestPushApi('token-a')
        ..bindWait = Completer<void>();
      final first = controller.sync(a);
      while (current.binds == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final second = controller.sync(a);
      current.bindWait!.complete();
      await Future.wait([first, second]);
      expect(current.unbinds, 0);
      expect(controller.binding, 'lease-token-a');
    },
  );
  test('disposed lifecycle callbacks cannot initialize or open push', () async {
    controller.dispose();
    await controller.sync(a);
    platform.callback!();
    expect(platform.initializations, 0);
    expect(routes, isEmpty);
  });
  test(
    'denied notification permission does not initialize SDK or enable push',
    () async {
      final api = apis['token-a'] = TestPushApi('token-a')
        ..p = const PushPreferences(configured: true);
      platform.permission = false;
      platform.requestAllowed = false;
      await controller.sync(a);
      await controller.update({'enabled': true});
      expect(api.saves, 0);
      expect(platform.initializations, 0);
      expect(controller.state.error, contains('未允许'));
    },
  );
  test('missing configuration is honest and does not initialize SDK', () async {
    platform.available = false;
    await controller.sync(a);
    await controller.update({'enabled': true});
    expect(platform.initializations, 0);
    expect(apis['token-a']!.saves, 0);
    expect(controller.state.error, isNotNull);
  });
  test('disable stops binding without losing station access', () async {
    await controller.sync(a);
    await controller.update({'enabled': false});
    expect(controller.state.preferences.enabled, isFalse);
    expect(apis['token-a']!.unbinds, 1);
  });
  test('failure keeps saved preferences and exposes recovery', () async {
    await controller.sync(a);
    apis['token-a']!.failSave = true;
    await controller.update({'tasks': false});
    expect(controller.state.preferences.tasks, isTrue);
    expect(controller.state.error, isNotNull);
  });
  test('click destinations are strictly whitelisted', () {
    expect(
      PushController.routeFor({
        'resource': 'https://evil.invalid',
        'objectId': 'x',
      }),
      isNull,
    );
    expect(
      PushController.routeFor({'resource': 'tasks', 'objectId': '../secrets'}),
      isNull,
    );
    expect(
      PushController.routeFor({
        'resource': 'membership',
        'objectId': '11111111-1111-1111-1111-111111111111',
      }),
      '/membership-result/11111111-1111-1111-1111-111111111111',
    );
  });
  testWidgets(
    'notification settings fit a narrow screen and report unavailable configuration',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      platform.available = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pushControllerProvider.overrideWith(
              (ref) => PushController(platform, (t) => TestPushApi(t), (_) {}),
            ),
          ],
          child: MaterialApp(theme: appTheme(), home: const PushSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('移动推送尚未配置，站内消息仍可正常使用。'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(find.byType(SwitchListTile).first)
            .onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
