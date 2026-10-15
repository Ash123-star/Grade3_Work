import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/draft_database.dart';
import '../../data/local/draft_store.dart';
import '../../data/local/secure_values.dart';
import '../../data/local/session_store.dart';
import '../config.dart';

final secureValuesProvider = Provider<SecureValues>(
  (ref) => const PlatformSecureValues(),
);
final draftDatabaseProvider = Provider<DraftDatabase>((ref) {
  final db = DraftDatabase.device();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});
final draftStoreProvider = Provider<DraftStore>(
  (ref) => DraftStore(
    ref.watch(draftDatabaseProvider),
    ref.watch(secureValuesProvider),
    namespace: AppConfig.mock ? 'explicit-demo' : AppConfig.baseUrl,
  ),
);
final sessionStoreProvider = Provider<SessionStore>(
  (ref) =>
      SessionStore(ref.watch(secureValuesProvider), server: AppConfig.baseUrl),
);
