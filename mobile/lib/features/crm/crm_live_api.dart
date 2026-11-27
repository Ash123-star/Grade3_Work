import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';

typedef CrmRow = Map<String, dynamic>;
typedef CrmPage = ({List<CrmRow> rows, int? next});

final liveCrmApiProvider = Provider(
  (ref) => LiveCrmApi(ref.watch(httpRepositoryProvider).dio),
);

class LiveCrmApi {
  LiveCrmApi(this._dio);
  final Dio _dio;
  static const _base = '/offline-deliveries';

  Future<CrmRow> _request(
    String path, {
    Map<String, Object>? query,
    CrmRow? body,
    String? key,
  }) async {
    try {
      final response = body == null
          ? await _dio.get<CrmRow>(path, queryParameters: query)
          : await _dio.post<CrmRow>(
              path,
              data: body,
              options: Options(headers: {'Idempotency-Key': ?key}),
            );
      return response.data ??
          (throw const ApiFailure(FailureKind.server, '服务响应不完整'));
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
    }
  }

  Future<CrmPage> _page(
    String path,
    int cursor,
    Map<String, Object> query,
  ) async {
    final value = await _request(
      path,
      query: {...query, 'cursor': cursor, 'limit': 10},
    );
    final rows = crmRows(value['items']);
    final next = int.tryParse('${value['nextCursor']}');
    final total = value['total'];
    return (
      rows: rows,
      next:
          rows.isNotEmpty &&
              next != null &&
              next > cursor &&
              (total is! int || next < total)
          ? next
          : null,
    );
  }

  Future<CrmPage> customers(int cursor, String search, String kind) =>
      _page('/customers', cursor, {'search': search, 'kind': kind});

  Future<CrmPage> employees(
    int cursor,
    String search, {
    required bool activeOnly,
  }) => _page('$_base/employees', cursor, {
    'search': search,
    'activeOnly': activeOnly,
  });

  Future<CrmPage> records(
    int cursor, {
    required String id,
    required bool byEmployee,
    required bool pendingOnly,
  }) => _page(_base, cursor, {
    (byEmployee ? 'employeeId' : 'customerId'): id,
    'pendingOnly': pendingOnly,
  });

  Future<CrmRow> detail(String id) =>
      _request('$_base/${Uri.encodeComponent(id)}');

  Future<CrmRow> create(CrmRow body, String key) =>
      _request(_base, body: body, key: key);

  Future<CrmRow> submit(String id, CrmRow body, String key) => _request(
    '$_base/${Uri.encodeComponent(id)}/changes',
    body: body,
    key: key,
  );

  Future<CrmRow> withdraw(String id) => _request(
    '/reviews/${Uri.encodeComponent(id)}/withdraw-offline',
    body: {},
  );
}

List<CrmRow> crmRows(Object? value) =>
    value is List ? value.whereType<CrmRow>().toList() : const [];

String crmValue(CrmRow row, String field) => row[field]?.toString() ?? '';
