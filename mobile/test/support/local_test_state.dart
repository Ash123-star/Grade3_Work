import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/data/local/draft_database.dart';
import 'package:pandora_mobile/data/local/secure_values.dart';

class MemorySecureValues implements SecureValues {
  final values = <String, String>{};
  bool failRead = false, failWrite = false, failRemove = false;
  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('test storage failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('test storage failure');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    if (failRemove) throw StateError('test storage failure');
    values.remove(key);
  }
}

List<Override> localTestOverrides() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return [
    secureValuesProvider.overrideWithValue(MemorySecureValues()),
    draftDatabaseProvider.overrideWith((ref) {
      final db = DraftDatabase(NativeDatabase.memory());
      ref.onDispose(() => db.close());
      return db;
    }),
  ];
}

ProviderContainer testContainer({List<Override> overrides = const []}) =>
    ProviderContainer(overrides: [...localTestOverrides(), ...overrides]);

/// Native SQLite and encryption futures can cross the fake/real test clock.
Future<void> settleLocalIo(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pump();
}

/// Await an observable completion rather than assuming native encryption/SQLite
/// finishes within a fixed 60 ms while the full suite is running concurrently.
Future<void> waitForLocalState(WidgetTester tester, Finder completion) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    if (completion.evaluate().isNotEmpty) return;
  }
  expect(completion, findsWidgets, reason: 'Local operation did not complete');
}
