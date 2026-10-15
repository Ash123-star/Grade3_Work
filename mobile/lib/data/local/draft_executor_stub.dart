import 'package:drift/drift.dart';
import 'secure_values.dart';

QueryExecutor openDraftDatabase() => LazyDatabase(() async {
  throw const LocalStorageFailure('当前浏览器不支持本机加密草稿，请使用Android应用；输入仍保留在当前页面');
});
