import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';

typedef CrmRow = Map<String, dynamic>;
typedef CrmPage = ({List<CrmRow> rows, int? next});

final liveCrmDeniedProvider = StateProvider.autoDispose.family<bool, int>(
  (ref, epoch) => false,
);

final liveCrmApiProvider = Provider.autoDispose((ref) {
  final denied = ref.watch(
    liveCrmDeniedProvider(ref.watch(sessionEpochProvider)).notifier,
  );
  var disposed = false;
  ref.onDispose(() => disposed = true);
  return LiveCrmApi(ref.watch(httpRepositoryProvider).dio, () {
    if (!disposed) denied.state = true;
  });
});

class LiveCrmApi {
  LiveCrmApi(this._dio, [this._onDenied]);
  final Dio _dio;
  final VoidCallback? _onDenied;
  static const _base = '/offline-deliveries';

  Future<CrmRow> _request(
    String path, {
    Map<String, Object>? query,
    CrmRow? body,
    String? key,
    String? method,
  }) => _read<CrmRow>(path, query: query, body: body, key: key, method: method);

  Future<T> _read<T>(
    String path, {
    Map<String, Object>? query,
    CrmRow? body,
    String? key,
    String? method,
  }) async {
    try {
      final response = await _dio.request<T>(
        path,
        queryParameters: query,
        data: body,
        options: Options(
          method: method ?? (body == null ? 'GET' : 'POST'),
          headers: {'Idempotency-Key': ?key},
        ),
      );
      return response.data ??
          (throw const ApiFailure(FailureKind.server, '服务响应不完整'));
    } on DioException catch (error) {
      final failure = ApiFailure.fromDio(error);
      if (failure.kind == FailureKind.unauthorized ||
          failure.kind == FailureKind.forbidden) {
        _onDenied?.call();
      }
      throw failure;
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

  String _customer(String id) => '/customers/${Uri.encodeComponent(id)}';

  Future<CrmRow> customer(String id) async {
    final detail = await _request(_customer(id));
    final profile = detail['customer'];
    if (profile is! CrmRow || profile['id'] != id) {
      throw const ApiFailure(FailureKind.server, '客户资料响应不完整');
    }
    return detail;
  }

  Future<CrmRow> createCustomer(CrmRow body, String key) =>
      _request('/customers', body: body, key: key);

  Future<CrmRow> updateCustomer(String id, CrmRow body) =>
      _request(_customer(id), body: body, method: 'PUT');

  Future<CrmRow> saveMembership(String id, CrmRow body) =>
      _request('${_customer(id)}/membership', body: body, method: 'PUT');

  Future<CrmRow> createBenefit(String id, CrmRow body, String key) =>
      _request('${_customer(id)}/benefits', body: body, key: key);

  String _redemptions(String id, String benefitId) =>
      '${_customer(id)}/benefits/${Uri.encodeComponent(benefitId)}/redemptions';

  Future<List<CrmRow>> redemptions(String id, String benefitId) async =>
      crmRows(await _read<List<dynamic>>(_redemptions(id, benefitId)));

  Future<CrmRow> redeem(String id, String benefitId, CrmRow body, String key) =>
      _request(_redemptions(id, benefitId), body: body, key: key);

  Future<CrmRow> addProgress(String id, CrmRow body, String key) =>
      _request('${_customer(id)}/progress', body: body, key: key);

  Future<CrmPage> orders(String customerId, int cursor) =>
      _page('/commerce/orders', cursor, {'customerId': customerId});

  Future<CrmRow> order(String customerId, String externalOrderId) async {
    final page = await _page('/commerce/orders', 0, {
      'customerId': customerId,
      'externalOrderId': externalOrderId,
    });
    return page.rows.firstWhere(
      (row) => row['externalOrderId'] == externalOrderId,
      orElse: () => throw const ApiFailure(FailureKind.notFound, '订单已不可见'),
    );
  }

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
