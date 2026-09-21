import 'package:dio/dio.dart';
import '../core/failure.dart';
import 'models.dart';

abstract interface class Repository {
  Future<PageResult> list(String resource, Query query);
  Future<Record> detail(String resource, String id);
  Future<Record> execute(String resource, Command command);
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
  @override
  Future<PageResult> list(String resource, Query query) async {
    try {
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
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  @override
  Future<Record> detail(String resource, String id) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/$resource/${Uri.encodeComponent(id)}',
      );
      return Record.fromJson(response.data!);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

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
