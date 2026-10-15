import 'package:drift/drift.dart';
import 'secure_values.dart';
import 'draft_executor_stub.dart'
    if (dart.library.io) 'draft_executor_native.dart'
    as platform;

/// Custom SQL keeps this small, encrypted-only schema free of generated DTOs.
class DraftDatabase extends GeneratedDatabase {
  DraftDatabase(super.executor);
  DraftDatabase.device() : super(platform.openDraftDatabase());
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => customStatement('''
      CREATE TABLE drafts (
        lookup_id TEXT NOT NULL PRIMARY KEY,
        ciphertext BLOB NOT NULL,
        nonce BLOB NOT NULL,
        mac BLOB NOT NULL
      )
    '''),
    onUpgrade: (_, _, _) =>
        throw const LocalStorageFailure('草稿存储版本不兼容，请保留设备数据并联系管理员'),
  );
}
