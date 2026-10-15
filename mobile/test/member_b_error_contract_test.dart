import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';

void main() {
  test('停用账号登录显示具体原因，同时保留服务端追踪标识', () {
    final request = RequestOptions(path: '/auth/login');
    final failure = ApiFailure.fromDio(DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: request,
        statusCode: 403,
        data: {'code': 'ACCOUNT_DISABLED'},
        headers: Headers.fromMap({'x-trace-id': ['disabled-account-test']}),
      ),
    ));
    expect(failure.message, '账号已停用，请联系管理员');
    expect(failure.kind, FailureKind.forbidden);
    expect(failure.traceId, 'disabled-account-test');
  });
}
