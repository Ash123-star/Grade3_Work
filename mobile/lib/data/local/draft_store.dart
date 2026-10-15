import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'draft_database.dart';
import 'secure_values.dart';

class DraftLocation {
  const DraftLocation({
    required this.account,
    required this.kind,
    required this.object,
  });
  factory DraftLocation.diary(String account, DateTime day) => DraftLocation(
    account: account,
    kind: 'diary',
    object:
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
  );
  factory DraftLocation.revision(String account, String id, int version) =>
      DraftLocation(account: account, kind: 'revision', object: '$id:$version');
  final String account, kind, object;
  String get legacyKey =>
      kind == 'diary' ? 'draft:$account:$object' : 'revision:$account:$object';
  List<String> get identity => [account, kind, object];
}

class LocalDraft {
  LocalDraft({
    required Map<String, String> fields,
    required this.savedAt,
    this.serverId,
    this.serverVersion,
  }) : fields = Map.unmodifiable(fields);
  final Map<String, String> fields;
  final DateTime savedAt;
  final String? serverId;
  final int? serverVersion;
}

/// All operations are ordered, including migration, readback and deletion.
class DraftStore {
  DraftStore(this.database, this.secure, {required this.namespace});
  final DraftDatabase database;
  final SecureValues secure;
  final String namespace;
  final _aes = AesGcm.with256bits();
  Future<void> _queue = Future.value();
  SecretKey? _encryptionKey, _lookupKey;
  static const legacyFields = ['今日工作', '关联任务', '遇到的阻碍', '明日计划', '工时', '修改理由'];

  Future<T> _ordered<T>(Future<T> Function() work) {
    final operation = _queue.then((_) => work());
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  String get keyName => 'pandora-draft-master-key:v1';
  Future<void> _keys() async {
    if (_encryptionKey != null) return;
    var encoded = await secure.read(keyName);
    if (encoded == null) {
      final count = await database
          .customSelect('SELECT COUNT(*) AS n FROM drafts')
          .getSingle();
      if (count.read<int>('n') != 0) {
        throw const LocalStorageFailure('草稿密钥不可用，请保留本机数据并重试');
      }
      final generated = await _aes.newSecretKey();
      encoded = base64Encode(await generated.extractBytes());
      await secure.write(keyName, encoded);
      if (await secure.read(keyName) != encoded) {
        throw const LocalStorageFailure('无法确认安全密钥已保存，请重试');
      }
    }
    final bytes = base64Decode(encoded);
    if (bytes.length != 32) throw const LocalStorageFailure('草稿密钥无效，请保留本机数据');
    final encryption = SecretKey(bytes);
    final lookup = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: encryption,
      nonce: utf8.encode('pandora-draft-v1'),
      info: utf8.encode('lookup'),
    );
    _encryptionKey = encryption;
    _lookupKey = lookup;
  }

  String _identity(DraftLocation location) {
    if (location.account.isEmpty || location.object.isEmpty) {
      throw const LocalStorageFailure('草稿账号或日期无效');
    }
    return jsonEncode([namespace, ...location.identity]);
  }

  Future<String> _lookup(DraftLocation location) async {
    await _keys();
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(_identity(location)),
      secretKey: _lookupKey!,
    );
    return base64Url.encode(mac.bytes);
  }

  Future<LocalDraft?> _read(DraftLocation location) async {
    final lookup = await _lookup(location);
    final row = await database
        .customSelect(
          'SELECT ciphertext, nonce, mac FROM drafts WHERE lookup_id = ?',
          variables: [Variable<String>(lookup)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final clear = await _aes.decrypt(
      SecretBox(
        row.read<Uint8List>('ciphertext'),
        nonce: row.read<Uint8List>('nonce'),
        mac: Mac(row.read<Uint8List>('mac')),
      ),
      secretKey: _encryptionKey!,
      aad: utf8.encode(lookup),
    );
    final data = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    if (data['identity'] != _identity(location) || data['schema'] != 1) {
      throw const LocalStorageFailure('草稿内容校验失败，请保留本机数据');
    }
    return LocalDraft(
      fields: Map<String, String>.from(data['fields'] as Map),
      savedAt: DateTime.parse(data['savedAt'] as String),
      serverId: data['serverId'] as String?,
      serverVersion: data['serverVersion'] as int?,
    );
  }

  Future<void> _write(DraftLocation location, LocalDraft draft) async {
    final lookup = await _lookup(location);
    final clear = utf8.encode(
      jsonEncode({
        'schema': 1,
        'identity': _identity(location),
        'fields': draft.fields,
        'savedAt': draft.savedAt.toIso8601String(),
        'serverId': draft.serverId,
        'serverVersion': draft.serverVersion,
      }),
    );
    if (clear.length > 1024 * 1024) {
      throw const LocalStorageFailure('草稿超过本机保存上限，请缩短正文后重试');
    }
    final box = await _aes.encrypt(
      clear,
      secretKey: _encryptionKey!,
      aad: utf8.encode(lookup),
    );
    await database.customStatement(
      '''
      INSERT INTO drafts (lookup_id, ciphertext, nonce, mac) VALUES (?, ?, ?, ?)
      ON CONFLICT(lookup_id) DO UPDATE SET
        ciphertext = excluded.ciphertext, nonce = excluded.nonce, mac = excluded.mac
    ''',
      [
        lookup,
        Uint8List.fromList(box.cipherText),
        Uint8List.fromList(box.nonce),
        Uint8List.fromList(box.mac.bytes),
      ],
    );
  }

  Future<void> _removeLegacy(
    SharedPreferences prefs,
    DraftLocation location,
  ) async {
    for (final field in [...legacyFields, 'savedAt']) {
      final key = '${location.legacyKey}:$field';
      if (prefs.containsKey(key) && !await prefs.remove(key)) {
        throw const LocalStorageFailure('旧草稿清理失败，请重试；新加密稿已保留');
      }
    }
  }

  Future<LocalDraft?> read(DraftLocation location) => _ordered(() async {
    try {
      final current = await _read(location);
      final prefs = await SharedPreferences.getInstance();
      if (current != null) {
        await _removeLegacy(prefs, location);
        return current;
      }
      final fields = <String, String>{
        for (final name in legacyFields)
          if (prefs.containsKey('${location.legacyKey}:$name'))
            name: prefs.getString('${location.legacyKey}:$name') ?? '',
      };
      if (fields.isEmpty) return null;
      final migrated = LocalDraft(
        fields: fields,
        savedAt:
            DateTime.tryParse(
              prefs.getString('${location.legacyKey}:savedAt') ?? '',
            ) ??
            DateTime.now(),
      );
      await database.transaction(() async {
        await _write(location, migrated);
        final verified = await _read(location);
        if (verified == null ||
            jsonEncode(verified.fields) != jsonEncode(fields)) {
          throw const LocalStorageFailure('草稿迁移校验失败，请重试');
        }
      });
      await _removeLegacy(prefs, location);
      return migrated;
    } on LocalStorageFailure {
      rethrow;
    } catch (_) {
      throw const LocalStorageFailure('无法读取加密草稿，请保留本机数据并重试');
    }
  });

  Future<void> write(DraftLocation location, LocalDraft draft) =>
      _ordered(() async {
        try {
          await _write(location, draft);
          await _removeLegacy(await SharedPreferences.getInstance(), location);
        } on LocalStorageFailure {
          rethrow;
        } catch (_) {
          throw const LocalStorageFailure('加密草稿保存失败，输入仍保留，请重试');
        }
      });

  Future<void> remove(DraftLocation location) => _ordered(() async {
    try {
      final lookup = await _lookup(location);
      await database.customStatement('DELETE FROM drafts WHERE lookup_id = ?', [
        lookup,
      ]);
      await _removeLegacy(await SharedPreferences.getInstance(), location);
    } catch (_) {
      throw const LocalStorageFailure('已提交，但本机草稿清理失败，请重试清理');
    }
  });
}
