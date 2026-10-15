import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        options.method == 'GET'
            ? [
                {'id': 'dept-tech', 'name': '技术部'},
              ]
            : {'id': 'pending-user', 'status': 'PENDING', 'role': 'EMPLOYEE'},
      ),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'registration reads public department IDs and sends selected ID',
    () async {
      final repository = HttpRepository('http://10.0.2.2:8080/api', null);
      final adapter = _Adapter();
      repository.dio.httpClientAdapter = adapter;
      final departments = await repository.list(
        'auth/departments',
        const Query(),
      );
      expect(departments.items.single.id, 'dept-tech');
      expect(departments.items.single.title, '技术部');
      await repository.execute(
        'auth',
        const Command('register', {
          '账号': 'employee',
          '密码': 'test-password-12',
          '手机号': '13900000000',
          '部门': '技术部',
          'departmentId': 'dept-tech',
        }),
      );
      expect(adapter.requests.first.path, '/auth/departments');
      expect((adapter.requests.last.data as Map)['departmentId'], 'dept-tech');
      expect((adapter.requests.last.data as Map).containsKey('role'), isFalse);
    },
  );
  test(
    'connection failures explain backend availability rather than credentials',
    () {
      final failure = ApiFailure.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(failure.kind, FailureKind.unavailable);
      expect(failure.message, contains('后端已启动'));
    },
  );
}
