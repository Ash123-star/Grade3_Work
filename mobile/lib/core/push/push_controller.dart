import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../errors/api_failure.dart';
import '../../data/models/models.dart';
import 'push_platform.dart';

class PushPreferences {
  const PushPreferences({
    this.configured = false,
    this.enabled = false,
    this.tasks = true,
    this.deadlines = true,
    this.reviews = true,
    this.quietEnabled = true,
    this.quietStart = 22,
    this.quietEnd = 8,
    this.version = 1,
  });
  factory PushPreferences.fromJson(Map m) => PushPreferences(
    configured: m['configured'] == true,
    enabled: m['enabled'] == true,
    tasks: m['tasks'] == true,
    deadlines: m['deadlines'] == true,
    reviews: m['reviews'] == true,
    quietEnabled: m['quietEnabled'] == true,
    quietStart: m['quietStart'] as int,
    quietEnd: m['quietEnd'] as int,
    version: m['version'] as int,
  );
  final bool configured, enabled, tasks, deadlines, reviews, quietEnabled;
  final int quietStart, quietEnd, version;
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'tasks': tasks,
    'deadlines': deadlines,
    'reviews': reviews,
    'quietEnabled': quietEnabled,
    'quietStart': quietStart,
    'quietEnd': quietEnd,
    'version': version,
  };
}

abstract interface class PushApi {
  Future<PushPreferences> preferences();
  Future<PushPreferences> save(Map<String, dynamic> body);
  Future<String> bind(String device);
  Future<void> unbind(String device);
  Future<Map> open(String id, String device, String binding);
  Future<Map> membership(String id);
  void close();
}

class HttpPushApi implements PushApi {
  HttpPushApi(String token)
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.baseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
  final Dio dio;
  Future<T> guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  @override
  Future<PushPreferences> preferences() => guard(
    () async =>
        PushPreferences.fromJson((await dio.get('/push/preferences')).data),
  );
  @override
  Future<PushPreferences> save(Map<String, dynamic> body) => guard(
    () async => PushPreferences.fromJson(
      (await dio.put('/push/preferences', data: body)).data,
    ),
  );
  @override
  Future<String> bind(String device) => guard(
    () async =>
        (await dio.put(
              '/push/device',
              data: {'deviceId': device},
            )).data['binding']
            as String,
  );
  @override
  Future<void> unbind(String device) => guard(() async {
    await dio.delete('/push/device', data: {'deviceId': device});
  });
  @override
  Future<Map> open(String id, String device, String binding) => guard(
    () async =>
        (await dio.get(
              '/push/open/${Uri.encodeComponent(id)}',
              queryParameters: {'deviceId': device, 'binding': binding},
            )).data
            as Map,
  );
  @override
  Future<Map> membership(String id) => guard(
    () async =>
        (await dio.get('/reviews/${Uri.encodeComponent(id)}')).data as Map,
  );
  @override
  void close() => dio.close(force: true);
}

class PushState {
  const PushState({
    this.preferences = const PushPreferences(),
    this.loading = false,
    this.permitted = false,
    this.clientConfigured = false,
    this.error,
  });
  final PushPreferences preferences;
  final bool loading, permitted, clientConfigured;
  final String? error;
}

final pushPlatformProvider = Provider<PushPlatform>(
  (ref) => AliyunPushPlatform(),
);
final pushApiFactoryProvider = Provider<PushApi Function(String)>(
  (ref) => HttpPushApi.new,
);
final pushRouteProvider = StateProvider<String?>((ref) => null);
final pushControllerProvider = StateNotifierProvider<PushController, PushState>(
  (ref) {
    final controller = PushController(
      ref.watch(pushPlatformProvider),
      ref.watch(pushApiFactoryProvider),
      (route) => ref.read(pushRouteProvider.notifier).state = route,
    );
    return controller;
  },
);

/// Serializes binding changes; late callbacks cannot overwrite another account's state.
class PushController extends StateNotifier<PushState> {
  PushController(this.platform, this.apiFactory, this.navigate)
    : super(const PushState()) {
    platform.onOpen(() {
      if (mounted) unawaited(consumeOpen());
    });
  }
  final PushPlatform platform;
  final PushApi Function(String) apiFactory;
  final void Function(String) navigate;
  Session? session;
  PushApi? api;
  String? device, binding;
  Map<String, dynamic>? pending;
  int epoch = 0;
  Object? requestedIdentity;
  bool opening = false;
  String? lastOpen;
  Future<void> syncTail = Future<void>.value();
  bool valid(int e) => mounted && e == epoch;
  Future<void> sync(Session next) {
    if (!mounted) return Future<void>.value();
    final identity = (
      next.id,
      next.companyId,
      next.token,
      next.status,
      next.expired,
      next.mustChangePassword,
    );
    if (requestedIdentity != identity) {
      requestedIdentity = identity;
      epoch++;
    }
    final e = epoch;
    return syncTail = syncTail.then((_) => syncSession(next, e));
  }

  Future<void> syncSession(Session next, int e) async {
    if (!valid(e)) return;
    final changed = session?.token != next.token || session?.id != next.id;
    final oldApi = api, oldDevice = device;
    session = next;
    if (changed) {
      api = null;
      device = null;
      binding = null;
      lastOpen = null;
    }
    try {
      if (!platform.supported || AppConfig.mock) return;
      pending ??= await platform.drainOpen();
      await platform.clear();
      if (changed && oldApi != null) {
        if (oldDevice != null) {
          try {
            await oldApi.unbind(oldDevice);
          } catch (_) {
            /* revoked sessions are already ineligible server-side */
          }
        }
        oldApi.close();
      }
      if (!valid(e)) return;
      if (next.token == null ||
          next.expired ||
          next.mustChangePassword ||
          next.status == 'DISABLED') {
        state = const PushState();
        return;
      }
      final currentApi = api ??= apiFactory(next.token!);
      state = PushState(
        preferences: changed ? const PushPreferences() : state.preferences,
        loading: true,
      );
      final p = await currentApi.preferences();
      final configured = await platform.configured();
      final permission = await platform.permitted();
      if (!valid(e)) return;
      state = PushState(
        preferences: p,
        clientConfigured: configured,
        permitted: permission,
      );
      if (p.enabled && p.configured && configured && permission) {
        final id = await platform.initialize();
        if (!valid(e)) return;
        final lease = await currentApi.bind(id);
        if (!valid(e)) {
          await currentApi.unbind(id);
          return;
        }
        device = id;
        binding = lease;
        await consumeOpen();
      } else if (device != null) {
        await currentApi.unbind(device!);
        device = null;
        binding = null;
      }
    } catch (_) {
      if (valid(e)) {
        state = PushState(
          preferences: state.preferences,
          clientConfigured: state.clientConfigured,
          permitted: state.permitted,
          error: '暂时无法同步通知设置，请重试',
        );
      }
    }
  }

  Future<void> update(Map<String, dynamic> changes) async {
    if (state.loading || api == null) return;
    final e = epoch, currentApi = api!;
    state = PushState(
      preferences: state.preferences,
      clientConfigured: state.clientConfigured,
      permitted: state.permitted,
      loading: true,
    );
    try {
      if (changes['enabled'] == true) {
        if (!state.preferences.configured || !state.clientConfigured) {
          throw StateError('移动推送尚未配置');
        }
        final permitted = await platform.requestPermission();
        if (!valid(e)) return;
        if (!permitted) {
          state = PushState(
            preferences: state.preferences,
            clientConfigured: state.clientConfigured,
            error: '系统未允许通知，可在系统设置中开启',
          );
          return;
        }
      }
      await currentApi.save({...state.preferences.toJson(), ...changes});
      if (!valid(e)) return;
      if (changes['enabled'] == false) {
        await platform.clear(discardOpen: true);
        pending = null;
      }
      await sync(session!);
    } catch (error) {
      if (valid(e)) {
        state = PushState(
          preferences: state.preferences,
          clientConfigured: state.clientConfigured,
          permitted: state.permitted,
          error: error is ApiFailure ? error.message : '通知设置未保存，请重试',
        );
      }
    }
  }

  Future<void> consumeOpen() async {
    if (!mounted || opening || !platform.supported) return;
    opening = true;
    final e = epoch;
    try {
      pending ??= await platform.drainOpen();
      final click = pending;
      if (click == null || api == null || binding == null || device == null) {
        return;
      }
      pending = null;
      if (click['binding'] != binding || click['notificationId'] is! String) {
        return;
      }
      final id = click['notificationId'] as String;
      if (lastOpen == id) return;
      final destination = await api!.open(id, device!, binding!);
      if (!valid(e)) return;
      final route = routeFor(destination);
      if (route == null) throw StateError('Invalid route');
      lastOpen = id;
      navigate(route);
    } catch (_) {
      if (valid(e)) {
        state = PushState(
          preferences: state.preferences,
          clientConfigured: state.clientConfigured,
          permitted: state.permitted,
          error: '该通知已失效或当前账号无权查看',
        );
      }
    } finally {
      opening = false;
    }
  }

  static String? routeFor(Map result) {
    final resource = result['resource'], id = result['objectId'];
    if (id is! String ||
        !RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
        ).hasMatch(id)) {
      return null;
    }
    if (resource == 'membership') {
      return '/membership-result/$id';
    }
    if (!['tasks', 'reviews'].contains(resource)) {
      return null;
    }
    return '/item/$resource/${Uri.encodeComponent(id)}';
  }

  @override
  void dispose() {
    epoch++;
    api?.close();
    super.dispose();
  }
}
