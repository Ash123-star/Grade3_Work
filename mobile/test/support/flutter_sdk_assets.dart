import 'dart:io';

/// 从实际测试运行器或显式 SDK 环境变量定位官方字体，避免绑定某位组员的磁盘。
String get materialIconsFontPath {
  final roots = <Directory>[];
  final configured = Platform.environment['FLUTTER_ROOT'];
  if (configured != null && configured.isNotEmpty) {
    roots.add(Directory(configured));
  }
  var current = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 12; depth++) {
    roots.add(current);
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  for (final root in roots) {
    final file = File(
      '${root.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (file.existsSync()) return file.path;
  }
  throw StateError(
    '无法定位 Flutter MaterialIcons 字体；请通过 flutter test 运行或设置 FLUTTER_ROOT。',
  );
}
