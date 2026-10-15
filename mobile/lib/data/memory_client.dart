import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config.dart';
import '../core/providers.dart';
import '../core/failure.dart';

abstract interface class MemoryClient {
  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  });
}

class HttpMemoryClient implements MemoryClient {
  HttpMemoryClient(String? token)
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
  final Dio dio;
  @override
  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    try {
      final result = await dio.request<Map<String, dynamic>>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
      return result.data!;
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }
}

final memoryClientProvider = Provider<MemoryClient>(
  (ref) => HttpMemoryClient(ref.watch(sessionProvider).token),
);
