import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';

void main() {
  test('日志修改窗口过期保留明确错误码并映射为不可编辑提示', () {
    final request = RequestOptions(path: '/logs/log-1/content');
    final failure = ApiFailure.fromDio(
      DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request,
          statusCode: 409,
          data: {'code': 'LOG_EDIT_WINDOW_EXPIRED'},
        ),
      ),
    );
    expect(failure.kind, FailureKind.conflict);
    expect(failure.code, 'LOG_EDIT_WINDOW_EXPIRED');
    expect(failure.message, '日报首次提交已满24小时，不能再修改或撤回');
  });

  test('停用账号登录显示具体原因，同时保留服务端追踪标识', () {
    final request = RequestOptions(path: '/auth/login');
    final failure = ApiFailure.fromDio(
      DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request,
          statusCode: 403,
          data: {'code': 'ACCOUNT_DISABLED'},
          headers: Headers.fromMap({
            'x-trace-id': ['disabled-account-test'],
          }),
        ),
      ),
    );
    expect(failure.message, '账号已停用，请联系管理员');
    expect(failure.kind, FailureKind.forbidden);
    expect(failure.traceId, 'disabled-account-test');
  });
}
