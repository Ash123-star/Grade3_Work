import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../core/failure.dart';

/// 单条 Server-Sent Event：事件名、序号与拼接后的数据。
class ServerEvent {
  const ServerEvent(this.event, this.id, this.data);
  final String event;
  final String? id;
  final String data;
}

/// SSE 客户端：用 Dio 的 stream 响应解析 text/event-stream，产出统一事件流。
/// 复用现有 Bearer 认证；通知流支持 Last-Event-ID 重放，AI 作业流收到 result 结束。
class SseClient {
  SseClient(String baseUrl, String? token)
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
          responseType: ResponseType.stream,
          // 流式响应没有固定接收间隔，关闭 receiveTimeout 以免长连接被切断。
          receiveTimeout: Duration.zero,
        ),
      );
  final Dio dio;

  /// 打开一条 SSE 连接并逐个产出事件；连接或非 2xx 以 ApiFailure 结束流。
  Stream<ServerEvent> connect(
    String path, {
    String? lastEventId,
    CancelToken? cancel,
  }) async* {
    final headers = <String, String>{};
    if (lastEventId != null) headers['Last-Event-ID'] = lastEventId;
    final ResponseBody body;
    try {
      final response = await dio.get<ResponseBody>(
        path,
        cancelToken: cancel,
        options: Options(headers: headers),
      );
      body = response.data!;
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
    String event = 'message';
    String? id;
    final data = StringBuffer();
    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.isEmpty) {
        if (data.isNotEmpty || event != 'message') {
          yield ServerEvent(event, id, data.toString());
        }
        event = 'message';
        id = null;
        data.clear();
        continue;
      }
      if (line.startsWith(':')) continue; // 注释/心跳行
      final colon = line.indexOf(':');
      final field = colon == -1 ? line : line.substring(0, colon);
      final value = colon == -1
          ? ''
          : line.substring(colon + 1).replaceFirst(' ', '');
      switch (field) {
        case 'event':
          event = value;
        case 'id':
          id = value;
        case 'data':
          if (data.isNotEmpty) data.write('\n');
          data.write(value);
      }
    }
  }

  /// 通知流：携带并更新 Last-Event-ID，断线后用游标重连复用服务端序号重放。
  Stream<ServerEvent> notifications({String lastEventId = '0'}) async* {
    var cursor = lastEventId;
    while (true) {
      try {
        await for (final event in connect(
          '/notifications/stream',
          lastEventId: cursor,
        )) {
          if (event.id != null && event.id!.isNotEmpty) cursor = event.id!;
          yield event;
        }
      } on ApiFailure catch (e) {
        // 鉴权失败不重连，交由上层处理；其余瞬时中断退避后用游标重连。
        if (e.kind == FailureKind.unauthorized ||
            e.kind == FailureKind.forbidden) {
          rethrow;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  /// AI 作业流：收到 event:result 视为完成并正常结束，不做无限重连。
  Stream<ServerEvent> aiJob(String id, {CancelToken? cancel}) async* {
    await for (final event in connect(
      '/ai/jobs/${Uri.encodeComponent(id)}/stream',
      cancel: cancel,
    )) {
      yield event;
      if (event.event == 'result') return;
    }
  }
}
