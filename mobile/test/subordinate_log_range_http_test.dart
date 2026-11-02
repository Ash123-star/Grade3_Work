import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

/// 断言下属日志列表和成员月历真实发出的 HTTP 请求，而不仅是 Repository 入参。
class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this.body);

  final Map<String, dynamic> body;
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  late HttpRepository repository;

  HttpRepository build(Map<String, dynamic> body) {
    final adapter = _CaptureAdapter(body);
    final built = HttpRepository('http://localhost/api', 'fixture-token');
    built.dio.httpClientAdapter = adapter;
    return built;
  }

  List<RequestOptions> requestsOf(HttpRepository repository) =>
      (repository.dio.httpClientAdapter as _CaptureAdapter).requests;

  setUp(() {
    repository = build({'items': <dynamic>[], 'total': 0});
  });

  test('subordinate log range request carries real from/to instead of date', () async {
    // BusinessRange 用上海零点表示业务日；UTC 化后仍应落在上海自然日边界。
    final from = DateTime.utc(2025, 7, 31, 16);
    final to = DateTime.utc(2025, 8, 1, 16);

    await repository.list(
      'logs/subordinates',
      Query(
        from: from,
        to: to,
        ownerId: 'member-1',
        departmentId: 'dept-1',
        search: '验收',
      ),
    );

    final request = requestsOf(repository).single;
    expect(request.path, '/logs/subordinates');
    final query = request.uri.queryParameters;
    expect(query['from'], from.toIso8601String());
    expect(query['to'], to.toIso8601String());
    expect(query.containsKey('date'), isFalse);
    expect(query.containsKey('period'), isFalse);
    expect(query['ownerId'], 'member-1');
    expect(query.containsKey('participantId'), isFalse);
    expect(query['departmentId'], 'dept-1');
    expect(query['search'], '验收');
    expect(query['limit'], '30');
  });

  test('subordinate log query without both ends keeps legacy date/period', () async {
    await repository.list(
      'logs/subordinates',
      Query(from: DateTime.utc(2025, 8, 1), ownerId: 'member-1'),
    );

    final query = requestsOf(repository).single.uri.queryParameters;
    expect(query['date'], '2025-08-01');
    expect(query['period'], 'day');
    expect(query.containsKey('from'), isFalse);
    expect(query.containsKey('to'), isFalse);
  });

  test('member month calendar sends ownerId and month and parses every status', () async {
    repository = build({
      'ownerId': 'member-1',
      'month': '2025-07',
      'employmentStartDate': '2024-06-01',
      'days': {
        '1': 'SUBMITTED',
        '2': 'MISSING',
        '3': 'FUTURE',
        '4': 'UNKNOWN',
      },
    });

    final month = await repository.memberLogMonth('member-1', DateTime(2025, 7));

    final request = requestsOf(repository).single;
    expect(request.path, '/logs/subordinates/calendar');
    expect(request.uri.queryParameters, {
      'ownerId': 'member-1',
      'month': '2025-07',
    });
    expect(month.ownerId, 'member-1');
    expect(month.month, DateTime(2025, 7));
    expect(month.employmentStartDate, DateTime(2024, 6, 1));
    expect(month.days, {
      1: MemberLogDayStatus.submitted,
      2: MemberLogDayStatus.missing,
      3: MemberLogDayStatus.future,
      4: MemberLogDayStatus.unknown,
    });
  });

  test('member month calendar accepts an unknown employment start date', () async {
    repository = build({
      'ownerId': 'member-2',
      'month': '2025-02',
      'employmentStartDate': null,
      'days': {'1': 'UNKNOWN', '28': 'UNKNOWN'},
    });

    final month = await repository.memberLogMonth('member-2', DateTime(2025, 2));

    expect(month.employmentStartDate, isNull);
    expect(month.days.length, 2);
    expect(month.days.values.every((day) => day == MemberLogDayStatus.unknown), isTrue);
  });

  test('member month calendar rejects a response for another member', () async {
    repository = build({
      'ownerId': 'someone-else',
      'month': '2025-07',
      'employmentStartDate': null,
      'days': <String, dynamic>{},
    });

    await expectLater(
      repository.memberLogMonth('member-1', DateTime(2025, 7)),
      throwsA(
        isA<ApiFailure>().having((error) => error.kind, 'kind', FailureKind.unavailable),
      ),
    );
  });
}
