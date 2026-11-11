import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import 'oss_cache.dart';

/// 集中接管Image.asset/AssetImage/SvgPicture.asset；安装清单与离线副本保留。
/// 不使用用户token，不能缓存或请求attachments等私有业务入口。
class OssAssetBundle extends CachingAssetBundle {
  OssAssetBundle({Dio? client, AssetBundle? fallback, OssDiskCache? cache})
    : _client =
          client ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.baseUrl,
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 8),
            ),
          ),
      _fallback = fallback ?? rootBundle,
      _cache = cache ?? OssDiskCache();

  static final instance = OssAssetBundle();
  final Dio _client;
  final AssetBundle _fallback;
  final OssDiskCache _cache;
  final _entries = <String, Map<String, dynamic>>{};
  final _pending = <String, Future<ByteData>>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;
  String _release = '';
  bool _enabled = false;
  Future<void>? _initializing;
  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  int networkLoads = 0;
  int cacheLoads = 0;
  int fallbackLoads = 0;
  static bool _publicAsset(String key) =>
      RegExp(r'^(assets|fonts|packages)/').hasMatch(key);

  Future<void> initialize({bool enabled = true}) {
    _enabled = enabled;
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    if (!_enabled) return;
    _lastAttempt = DateTime.now();
    try {
      final response = await _client.get<dynamic>('/assets/manifest');
      final raw = response.data is String
          ? response.data as String
          : jsonEncode(response.data);
      _manifest(raw);
      await _cache.write('manifest', Uint8List.fromList(utf8.encode(raw)));
    } catch (_) {
      try {
        final bytes = await _cache.read('manifest');
        if (bytes != null) _manifest(utf8.decode(bytes));
      } catch (_) {
        // 最后一个manifest损坏时沿用安装包，不阻塞启动。
      }
    }
  }

  void _manifest(String raw) {
    if (raw.length > 4 * 1024 * 1024) {
      throw const FormatException('Manifest too large');
    }
    final manifest = jsonDecode(raw) as Map<String, dynamic>;
    final release = manifest['release'] as String;
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(release)) {
      throw const FormatException('Invalid asset release');
    }
    final entries = <String, Map<String, dynamic>>{};
    for (final raw in manifest['items'] as List) {
      final item = raw as Map<String, dynamic>;
      final path = item['path'] as String;
      if (!_publicAsset(path)) continue;
      if (path.contains('\\') ||
          path.contains('%') ||
          path.split('/').any((p) => p.isEmpty || p == '.' || p == '..') ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(item['hash'] as String) ||
          item['size'] is! int ||
          (item['size'] as int) < 1 ||
          (item['size'] as int) > 100 * 1024 * 1024) {
        throw const FormatException('Invalid asset entry');
      }
      entries[path] = item;
    }
    _release = release;
    _entries
      ..clear()
      ..addAll(entries);
    clear();
  }

  Future<bool> _valid(Uint8List bytes, Map<String, dynamic> item) async {
    if (bytes.length != item['size']) return false;
    final hash = await Sha256().hash(bytes);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join() ==
        item['hash'];
  }

  @override
  Future<ByteData> load(String key) => _pending.putIfAbsent(
    key,
    () => _load(key).whenComplete(() {
      _pending.remove(key);
    }),
  );

  Future<ByteData> _load(String key) async {
    if (_enabled &&
        _publicAsset(key) &&
        _entries.isEmpty &&
        DateTime.now().difference(_lastAttempt) > const Duration(seconds: 30)) {
      await initialize();
    }
    final item = _enabled ? _entries[key] : null;
    if (item != null) {
      final release = _release;
      final hash = item['hash'] as String;
      try {
        final cached = await _cache.read(hash);
        if (cached != null && await _valid(cached, item)) {
          cacheLoads++;
          return ByteData.sublistView(cached);
        }
        if (_active >= 4) {
          final waiter = Completer<void>();
          _waiting.add(waiter);
          await waiter.future;
        } else {
          _active++;
        }
        try {
          final path = key.split('/').map(Uri.encodeComponent).join('/');
          final response = await _client.get<List<int>>(
            '/assets/$release/$path',
            options: Options(responseType: ResponseType.bytes),
          );
          final bytes = Uint8List.fromList(response.data!);
          if (!await _valid(bytes, item)) {
            throw const FormatException('Asset integrity error');
          }
          await _cache.write(hash, bytes);
          networkLoads++;
          return ByteData.sublistView(bytes);
        } finally {
          if (_waiting.isNotEmpty) {
            _waiting.removeFirst().complete();
          } else {
            _active--;
          }
        }
      } on Exception {
        // 失败不写缓存；下一次读取可以重试网络。
      }
    }
    fallbackLoads++;
    return _fallback.load(key);
  }

  Future<void> loadDisplayFont() async {
    await _initializing;
    if (!_enabled) return;
    try {
      if (_entries.containsKey('fonts/FontManifest.json')) {
        final data = await load('fonts/FontManifest.json');
        final families = jsonDecode(
          utf8.decode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ),
        );
        if (families is! List) return;
        await Future.wait(
          families.map((family) async {
            if (family is! Map ||
                family['family'] is! String ||
                family['fonts'] is! List) {
              return;
            }
            final loader = FontLoader(family['family'] as String);
            var count = 0;
            for (final font in family['fonts'] as List) {
              if (font is Map &&
                  font['asset'] is String &&
                  _entries.containsKey(font['asset'])) {
                loader.addFont(load(font['asset'] as String));
                count++;
              }
            }
            if (count > 0) await loader.load();
          }),
        );
      } else if (_entries.containsKey('assets/fonts/GenSenRoundedTW-B.ttf')) {
        final loader = FontLoader('TuantuanDisplay');
        loader.addFont(load('assets/fonts/GenSenRoundedTW-B.ttf'));
        await loader.load();
      }
    } on Exception {
      // Flutter的原有字体声明继续提供离线副本。
    }
  }
}
