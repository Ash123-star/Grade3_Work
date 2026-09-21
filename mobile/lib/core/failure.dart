import 'package:dio/dio.dart';

enum FailureKind {
  timeout,
  unauthorized,
  forbidden,
  validation,
  notFound,
  conflict,
  server,
  unavailable,
}

class ApiFailure implements Exception {
  const ApiFailure(this.kind, this.message, {this.traceId});
  final FailureKind kind;
  final String message;
  final String? traceId;
  factory ApiFailure.fromDio(DioException e) {
    final kind = switch (e.response?.statusCode) {
      401 => FailureKind.unauthorized,
      403 => FailureKind.forbidden,
      404 => FailureKind.notFound,
      409 => FailureKind.conflict,
      400 || 422 => FailureKind.validation,
      _ =>
        [
              DioExceptionType.connectionTimeout,
              DioExceptionType.receiveTimeout,
              DioExceptionType.sendTimeout,
            ].contains(e.type)
            ? FailureKind.timeout
            : FailureKind.server,
    };
    final message = switch (kind) {
      FailureKind.unauthorized => '登录已失效，请重新登录',
      FailureKind.forbidden => '你没有访问这项内容的权限',
      FailureKind.notFound => '内容不存在或已被移除',
      FailureKind.conflict => '内容已有新版本，请刷新后再提交',
      FailureKind.validation => '请检查填写的内容',
      FailureKind.timeout => '连接超时，请稍后重试',
      _ => '服务暂时不可用，请稍后重试',
    };
    return ApiFailure(
      kind,
      message,
      traceId: e.response?.headers.value('x-trace-id'),
    );
  }
  @override
  String toString() => message;
}
