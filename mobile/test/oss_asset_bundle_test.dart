import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/assets/oss_asset_bundle.dart';
import 'package:pandora_mobile/core/assets/oss_cache.dart';

class MemoryProductCache extends OssDiskCache {
  final values = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Uint8List bytes) async {
    values[key] = bytes;
  }
}

class LocalAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode('local')));
}

class ProductAdapter implements HttpClientAdapter {
  ProductAdapter(this.manifest, this.bytes);
  final Map<String, dynamic> manifest;
  final List<int> bytes;
  final paths = <String>[];
  bool offline = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    if (offline) throw DioException(requestOptions: options);
    if (options.path == '/assets/manifest') {
      return ResponseBody.fromString(
        jsonEncode(manifest),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<Map<String, dynamic>> manifest(
    List<int> bytes, {
    String path = 'assets/art.svg',
  }) async {
    final hash = (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return {
      'release': 'test-v1',
      'items': [
        {
          'path': path,
          'hash': hash,
          'size': bytes.length,
          'mime': 'image/svg+xml',
        },
      ],
    };
  }

  String text(ByteData data) => utf8.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );

  test(
    'remote bytes are verified and subsequent reads use content cache',
    () async {
      final bytes = utf8.encode('<svg/>');
      final adapter = ProductAdapter(await manifest(bytes), bytes);
      final dio = Dio()..httpClientAdapter = adapter;
      final bundle = OssAssetBundle(
        client: dio,
        fallback: LocalAssets(),
        cache: MemoryProductCache(),
      );
      await bundle.initialize();
      expect(text(await bundle.load('assets/art.svg')), '<svg/>');
      expect(text(await bundle.load('assets/art.svg')), '<svg/>');
      expect(bundle.networkLoads, 1);
      expect(bundle.cacheLoads, 1);
      expect(adapter.paths, [
        '/assets/manifest',
        '/assets/test-v1/assets/art.svg',
      ]);
    },
  );

  test('offline restart uses last manifest and verified bytes', () async {
    final bytes = utf8.encode('remote-art');
    final adapter = ProductAdapter(await manifest(bytes), bytes);
    final cache = MemoryProductCache();
    final dio = Dio()..httpClientAdapter = adapter;
    final first = OssAssetBundle(
      client: dio,
      fallback: LocalAssets(),
      cache: cache,
    );
    await first.initialize();
    await first.load('assets/art.svg');
    adapter.offline = true;
    final second = OssAssetBundle(
      client: dio,
      fallback: LocalAssets(),
      cache: cache,
    );
    await second.initialize();
    expect(text(await second.load('assets/art.svg')), 'remote-art');
    expect(second.networkLoads, 0);
    expect(second.cacheLoads, 1);
  });

  test(
    'dependency artwork and icon fonts use the same verified public loader',
    () async {
      for (final path in [
        'packages/cute_ui/assets/openmoji/1F431.svg',
        'fonts/MaterialIcons-Regular.otf',
      ]) {
        final bytes = utf8.encode('dependency-resource');
        final adapter = ProductAdapter(
          await manifest(bytes, path: path),
          bytes,
        );
        final bundle = OssAssetBundle(
          client: Dio()..httpClientAdapter = adapter,
          fallback: LocalAssets(),
          cache: MemoryProductCache(),
        );
        await bundle.initialize();
        expect(text(await bundle.load(path)), 'dependency-resource');
        expect(bundle.networkLoads, 1);
        expect(adapter.paths.last, '/assets/test-v1/$path');
      }
    },
  );

  test(
    'corrupt response falls back and is never added to content cache',
    () async {
      final adapter = ProductAdapter(
        await manifest(utf8.encode('valid')),
        utf8.encode('invalid'),
      );
      final cache = MemoryProductCache();
      final bundle = OssAssetBundle(
        client: Dio()..httpClientAdapter = adapter,
        fallback: LocalAssets(),
        cache: cache,
      );
      await bundle.initialize();
      expect(text(await bundle.load('assets/art.svg')), 'local');
      expect(cache.values.keys, ['manifest']);
      expect(bundle.fallbackLoads, 1);
    },
  );

  test(
    'private paths and mock mode never use the public network loader',
    () async {
      final adapter = ProductAdapter(
        await manifest(utf8.encode('art')),
        utf8.encode('art'),
      );
      final bundle = OssAssetBundle(
        client: Dio()..httpClientAdapter = adapter,
        fallback: LocalAssets(),
        cache: MemoryProductCache(),
      );
      await bundle.initialize(enabled: false);
      expect(text(await bundle.load('assets/art.svg')), 'local');
      expect(adapter.paths, isEmpty);
      await bundle.initialize();
      expect(text(await bundle.load('attachments/private-id')), 'local');
      expect(adapter.paths, ['/assets/manifest']);
    },
  );
}
