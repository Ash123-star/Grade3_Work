import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class PushPlatform {
  bool get supported;
  Future<bool> configured();
  Future<bool> permitted();
  Future<bool> requestPermission();
  Future<String> initialize();
  Future<void> clear({bool discardOpen = false});
  Future<Map<String, dynamic>?> drainOpen();
  Future<void> settings();
  void onOpen(void Function() callback);
}

class AliyunPushPlatform implements PushPlatform {
  static const channel = MethodChannel('pandora/push');
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<bool> configured() async {
    if (!supported) return false;
    return await channel.invokeMethod<bool>('configured') ?? false;
  }

  @override
  Future<bool> permitted() async =>
      supported && (await channel.invokeMethod<bool>('status') ?? false);
  @override
  Future<bool> requestPermission() async =>
      await channel.invokeMethod<bool>('requestPermission') ?? false;
  @override
  Future<String> initialize() async {
    await channel.invokeMethod('channels');
    final id =
        await channel
            .invokeMethod<String>('initialize')
            .timeout(const Duration(seconds: 15)) ??
        '';
    if (id.isEmpty) throw StateError('暂未获取到设备标识，请重试');
    return id;
  }

  @override
  Future<void> clear({bool discardOpen = false}) async {
    if (supported) {
      await channel.invokeMethod('clear', {'discardOpen': discardOpen});
    }
  }

  @override
  Future<Map<String, dynamic>?> drainOpen() =>
      channel.invokeMapMethod<String, dynamic>('drainOpen');
  @override
  Future<void> settings() async {
    if (supported) await channel.invokeMethod('settings');
  }

  @override
  void onOpen(void Function() callback) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'opened') callback();
    });
  }
}
