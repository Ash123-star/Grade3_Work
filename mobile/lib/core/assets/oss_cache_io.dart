import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// 只缓存公开产品素材，缓存Key是内容哈希，不接受私有附件路径。
class OssDiskCache {
  Future<Directory>? _directory;
  Future<File> _file(String key) async {
    if (!RegExp(r'^[a-z0-9_-]{1,100}$').hasMatch(key)) {
      throw ArgumentError('Invalid cache key');
    }
    final directory = await (_directory ??= () async {
      final root = await getApplicationCacheDirectory();
      return Directory(
        '${root.path}/oss_product_assets',
      ).create(recursive: true);
    }());
    return File('${directory.path}/$key');
  }

  Future<Uint8List?> read(String key) async {
    try {
      final file = await _file(key);
      return await file.exists() ? await file.readAsBytes() : null;
    } on Exception {
      return null;
    }
  }

  Future<void> write(String key, Uint8List bytes) async {
    try {
      final file = await _file(key);
      final pending = File('${file.path}.pending');
      await pending.writeAsBytes(bytes, flush: true);
      await pending.rename(file.path);
    } on Exception {
      // 缓存不可写时仍允许本次使用已验证的远程素材。
    }
  }
}
