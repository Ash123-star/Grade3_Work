import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/ai.dart';

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(httpRepositoryProvider).dio),
);

/// Existing server AI contracts; never calls a model provider or holds provider keys.
class AiRepository {
  AiRepository(this.dio);
  final Dio dio;
  String path(String id) {
    if (id.trim().isEmpty) {
      throw const ApiFailure(FailureKind.validation, '分析标识无效');
    }
    return '/ai/jobs/${Uri.encodeComponent(id)}';
  }

  Future<Map<String, dynamic>> request(
    String method,
    String url, {
    Map<String, dynamic>? data,
    CancelToken? token,
    String? idem,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        url,
        data: data,
        cancelToken: token,
        options: Options(method: method, headers: {'Idempotency-Key': ?idem}),
      );
      return aiObject(response.data);
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  Future<AiJob> create(
    String date,
    String period, {
    String purpose = 'SUMMARY',
    String? focus,
    CancelToken? token,
  }) async {
    if (DateTime.tryParse(date) == null ||
        !['day', 'week', 'month'].contains(period) ||
        ![
          'SUMMARY',
          'EXPLAIN_RISK',
          'SPLIT_STEPS',
          'DRAFT_TASK',
        ].contains(purpose) ||
        (purpose != 'SUMMARY' && (focus == null || focus.isEmpty))) {
      throw const ApiFailure(FailureKind.validation, '请选择有效日期、周期与来源');
    }
    return AiJob.fromJson(
      await request(
        'POST',
        '/ai/jobs',
        token: token,
        data: {
          'date': date,
          'period': period,
          'purpose': purpose,
          'focusSourceId': ?focus,
        },
      ),
    );
  }

  Future<AiJob> job(String id, {CancelToken? token}) async =>
      AiJob.fromJson(await request('GET', path(id), token: token));
  Future<void> cancel(String id, {CancelToken? token}) async {
    await request('DELETE', path(id), token: token);
  }

  Future<AiJob> retry(String id, {CancelToken? token}) async =>
      AiJob.fromJson(await request('POST', '${path(id)}/retry', token: token));
  Future<AiJob> edit(
    AiJob job,
    String summary,
    List<String> titles, {
    CancelToken? token,
  }) async {
    if (job.state != 'SUCCEEDED' ||
        summary.trim().isEmpty ||
        titles.length != job.actions.length ||
        titles.any((s) => s.trim().isEmpty)) {
      throw const ApiFailure(FailureKind.validation, '请填写分析正文和每条建议');
    }
    return AiJob.fromJson(
      await request(
        'PUT',
        '${path(job.id)}/draft',
        data: job.draft(summary.trim(), titles.map((s) => s.trim()).toList()),
        token: token,
      ),
    );
  }

  Future<Map<String, dynamic>> map({CancelToken? token}) =>
      request('GET', '/ai-maps', token: token);
  Future<Map<String, dynamic>> usage({CancelToken? token}) =>
      request('GET', '/ai/usage', token: token);
  Future<void> edge(
    String source,
    String target,
    String label, {
    CancelToken? token,
  }) async {
    if (source.isEmpty || target.isEmpty || source == target) {
      throw const ApiFailure(FailureKind.validation, '请选择两个不同节点');
    }
    await request(
      'POST',
      '/ai-maps/edges',
      data: {'sourceId': source, 'targetId': target, 'label': label},
      token: token,
    );
  }

  Future<String> confirm(
    AiJob job,
    int index,
    Map<String, dynamic> task,
    String idem, {
    CancelToken? token,
  }) async {
    if (job.state != 'SUCCEEDED' ||
        index < 0 ||
        index >= job.actions.length ||
        idem.trim().isEmpty ||
        '${task['title'] ?? ''}'.trim().isEmpty ||
        '${task['ownerId'] ?? ''}'.isEmpty ||
        !(DateTime.tryParse('${task['deadline']}')?.isAfter(DateTime.now()) ??
            false)) {
      throw const ApiFailure(FailureKind.validation, '请确认有效建议、负责人、任务名称与未来截止时间');
    }
    final result = await request(
      'POST',
      '${path(job.id)}/confirm-task',
      data: {'actionIndex': index, 'task': task},
      token: token,
      idem: idem,
    );
    if (result['id'] is! String || '${result['id']}'.isEmpty) {
      throw const ApiFailure(FailureKind.server, '任务创建响应不完整，请用原内容重试');
    }
    return result['id'];
  }

  Stream<AiStreamEvent> stream(String id, CancelToken token) async* {
    try {
      final response = await dio.get<ResponseBody>(
        '${path(id)}/stream',
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 60),
          headers: {'Accept': 'text/event-stream'},
        ),
      );
      if (!(response.headers.value('content-type') ?? '').startsWith(
        'text/event-stream',
      )) {
        throw const ApiFailure(FailureKind.server, '流式响应格式无效，请刷新状态');
      }
      yield* parseAiEvents(response.data!.stream);
    } on DioException catch (e) {
      if (!token.isCancelled) throw ApiFailure.fromDio(e);
    } on FormatException {
      throw const ApiFailure(FailureKind.server, '流式内容无法读取，请刷新状态');
    }
  }
}

Stream<AiStreamEvent> parseAiEvents(Stream<List<int>> bytes) async* {
  var kind = 'message', size = 0;
  final data = <String>[];
  await for (final line
      in bytes
          .map<List<int>>((chunk) => chunk)
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    size += line.length;
    // A result includes both bounded input and the completed output.
    if (size > 150000) {
      throw const ApiFailure(FailureKind.server, '流式内容过长，请刷新状态');
    }
    if (line.isEmpty) {
      if (data.isNotEmpty && ['delta', 'result'].contains(kind)) {
        yield AiStreamEvent(kind, aiObject(jsonDecode(data.join('\n'))));
      }
      data.clear();
      kind = 'message';
      size = 0;
    } else if (line.startsWith('event:')) {
      kind = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      var content = line.substring(5);
      if (content.startsWith(' ')) content = content.substring(1);
      data.add(content);
    }
  }
}
