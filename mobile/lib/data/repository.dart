import 'package:dio/dio.dart';
import '../core/failure.dart';
import 'models.dart';

abstract interface class Repository {
  Future<PageResult> list(String resource, Query query);
  Future<Record> detail(String resource, String id);
  Future<Record> execute(String resource, Command command);
}

/// 仅幂等 GET 在瞬时失败时重试：连接/超时/503，最多 2 次，退避 300ms、900ms。
/// 写请求（含带幂等键的派发）不自动重试，由上层用户动作决定是否重发。
const _retryBackoff = [Duration(milliseconds: 300), Duration(milliseconds: 900)];

bool _transient(DioException e) {
  if (e.response?.statusCode == 503) return true;
  return const [
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.sendTimeout,
  ].contains(e.type);
}

class HttpRepository implements Repository {
  HttpRepository(String baseUrl, String? token)
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
  final Dio dio;

  Future<T> _getWithRetry<T>(Future<T> Function() send) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await send();
      } on DioException catch (e) {
        if (attempt >= _retryBackoff.length || !_transient(e)) {
          throw ApiFailure.fromDio(e);
        }
        await Future<void>.delayed(_retryBackoff[attempt]);
      }
    }
  }

  @override
  Future<PageResult> list(String resource, Query query) => _getWithRetry(() async {
    final response = await dio.get<Map<String, dynamic>>(
      '/$resource',
      queryParameters: query.toJson(),
    );
    final json = response.data!;
    return PageResult(
      (json['items'] as List)
          .map((x) => Record.fromJson(Map<String, dynamic>.from(x)))
          .toList(),
      total: json['total'] as int? ?? 0,
      nextCursor: json['nextCursor'] as String?,
    );
  });

  @override
  Future<Record> detail(String resource, String id) => _getWithRetry(() async {
    final response = await dio.get<Map<String, dynamic>>(
      '/$resource/${Uri.encodeComponent(id)}',
    );
    return Record.fromJson(response.data!);
  });

  @override
  Future<Record> execute(String resource, Command command) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/$resource',
        data: command.toJson(),
        options: Options(
          headers: {
            if (command.idempotencyKey != null)
              'Idempotency-Key': command.idempotencyKey,
          },
        ),
      );
      return Record.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }
}
