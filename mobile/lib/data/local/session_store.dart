import 'dart:convert';
import '../models/models.dart';
import 'secure_values.dart';

class StoredCredential {
  const StoredCredential({
    required this.account,
    required this.token,
    required this.expiresAt,
  });
  final String account, token;
  final DateTime expiresAt;
}

class SessionStore {
  SessionStore(this.secure, {required this.server});
  final SecureValues secure;
  final String server;
  Future<void> _queue = Future.value();
  String get key => 'session:v1:${base64Url.encode(utf8.encode(server))}';
  Future<T> _ordered<T>(Future<T> Function() work) {
    final operation = _queue.then((_) => work());
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<StoredCredential?> read() => _ordered(() async {
    try {
      final raw = await secure.read(key);
      if (raw == null) return null;
      StoredCredential? credential;
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final date = DateTime.parse(data['expiresAt'] as String);
        final account = data['account'] as String,
            token = data['token'] as String;
        if (data['server'] == server &&
            data['schema'] == 1 &&
            account.isNotEmpty &&
            token.isNotEmpty &&
            date.isAfter(DateTime.now())) {
          credential = StoredCredential(
            account: account,
            token: token,
            expiresAt: date,
          );
        }
      } catch (_) {
        /* Invalid material is removed, never used as identity. */
      }
      if (credential == null) await secure.remove(key);
      return credential;
    } catch (_) {
      throw const LocalStorageFailure('无法读取安全会话，请重试或清除会话后登录');
    }
  });

  Future<void> save(Session session) => _ordered(() async {
    try {
      final token = session.token, date = session.expiresAt;
      if (token == null ||
          date == null ||
          session.id.isEmpty ||
          !date.isAfter(DateTime.now())) {
        await secure.remove(key);
        return;
      }
      await secure.write(
        key,
        jsonEncode({
          'schema': 1,
          'server': server,
          'account': session.id,
          'token': token,
          'expiresAt': date.toIso8601String(),
        }),
      );
    } catch (_) {
      throw const LocalStorageFailure('安全会话保存失败，本次登录仅在当前运行期间有效');
    }
  });

  /// Conditional clearing cannot revoke a replacement account after a late401.
  Future<void> clear({String? token}) => _ordered(() async {
    try {
      if (token != null) {
        final raw = await secure.read(key);
        if (raw == null) return;
        try {
          if ((jsonDecode(raw) as Map)['token'] != token) return;
        } catch (_) {
          /* Invalid data must also be cleared. */
        }
      }
      await secure.remove(key);
    } catch (_) {
      throw const LocalStorageFailure('安全会话清理失败，请重试');
    }
  });
}
