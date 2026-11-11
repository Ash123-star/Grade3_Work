import 'dart:typed_data';

class OssDiskCache {
  final _values = <String, Uint8List>{};
  Future<Uint8List?> read(String key) async => _values[key];
  Future<void> write(String key, Uint8List bytes) async {
    _values[key] = bytes;
  }
}
