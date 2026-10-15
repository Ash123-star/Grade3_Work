import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

QueryExecutor openDraftDatabase() => LazyDatabase(() async {
  final directory = await getApplicationSupportDirectory();
  return NativeDatabase.createInBackground(
    File(path.join(directory.path, 'private-drafts-v1.sqlite')),
  );
});
