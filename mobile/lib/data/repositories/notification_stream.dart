import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/errors/api_failure.dart';

/// Metadata only. The stream never substitutes for an authorized list read.
class NotificationSignal {
  const NotificationSignal(this.sequence);
  final int? sequence;
}

class NotificationStream {
  NotificationStream(this.dio);
  final Dio dio;
  Stream<NotificationSignal> connect(int after, CancelToken cancel) {
    late StreamController<NotificationSignal> output;
    Future<void> run() async {
      StreamController<List<int>>? bridge;
      var parsedFinished = false;
      try {
        if (after < 0) throw const ApiFailure(FailureKind.validation, '消息序号无效');
        final response = await dio.get<ResponseBody>(
          '/notifications/stream',
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(seconds: 70),
            headers: {'Accept': 'text/event-stream', 'Last-Event-ID': '$after'},
          ),
        );
        if (response.data == null) {
          throw const ApiFailure(FailureKind.validation, '消息连接格式无效，请重新连接');
        }
        // Keep this listener until Dio's cancellation is delivered. Canceling the
        // outer subscription must not leave Dio's response sink without a listener.
        bridge = StreamController<List<int>>();
        final relay = bridge;
        response.data!.stream.listen(
          (chunk) {
            if (!parsedFinished && !relay.isClosed) relay.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            if (!parsedFinished && !relay.isClosed) {
              relay.addError(error, stack);
            }
          },
          onDone: () {
            if (!relay.isClosed) unawaited(relay.close());
          },
        );
        if (!(response.headers.value('content-type') ?? '')
            .toLowerCase()
            .startsWith('text/event-stream')) {
          throw const ApiFailure(FailureKind.validation, '消息连接格式无效，请重新连接');
        }
        if (cancel.isCancelled) return;
        if (!output.isClosed) output.add(const NotificationSignal(null));
        await for (final signal in parseNotificationSignals(relay.stream)) {
          if (!output.isClosed && !cancel.isCancelled) output.add(signal);
        }
      } catch (error, stack) {
        if (!cancel.isCancelled && !output.isClosed) {
          final failure = error is DioException
              ? ApiFailure.fromDio(error)
              : error is FormatException
              ? const ApiFailure(FailureKind.validation, '消息流无法读取，请重新连接')
              : error;
          output.addError(failure, stack);
        }
      } finally {
        parsedFinished = true;
        cancel.cancel();
        if (bridge != null && !bridge.isClosed) unawaited(bridge.close());
        if (!output.isClosed) unawaited(output.close());
      }
    }

    output = StreamController<NotificationSignal>(
      onListen: () => unawaited(run()),
      onCancel: () => cancel.cancel(),
    );
    return output.stream;
  }
}

Stream<NotificationSignal> parseNotificationSignals(
  Stream<List<int>> bytes,
) async* {
  var event = 'message', id = '', size = 0;
  final data = <String>[];
  // Frame limit applies before line splitting, including an unterminated line.
  Stream<List<int>> bounded() async* {
    var count = 0;
    var previousNewline = false;
    await for (final chunk in bytes) {
      for (final b in chunk) {
        if (++count > 65536) throw const FormatException('oversized SSE frame');
        if (b == 10) {
          if (previousNewline) count = 0;
          previousNewline = true;
        } else if (b != 13) {
          previousNewline = false;
        }
      }
      yield chunk;
    }
  }

  await for (final line
      in bounded().transform(utf8.decoder).transform(const LineSplitter())) {
    size += line.length;
    if (size > 65536) throw const FormatException('oversized SSE frame');
    if (line.isEmpty) {
      if (event == 'notification' && data.isNotEmpty) {
        final sequence = RegExp(r'^[1-9]\d*$').hasMatch(id)
            ? int.tryParse(id)
            : null;
        final raw = jsonDecode(data.join('\n'));
        if (sequence == null ||
            raw is! Map ||
            raw['sequence'] is! int ||
            raw['sequence'] != sequence ||
            raw['id'] is! String ||
            (raw['id'] as String).isEmpty) {
          throw const FormatException('invalid notification sequence');
        }
        yield NotificationSignal(sequence);
      }
      event = 'message';
      id = '';
      size = 0;
      data.clear();
    } else if (!line.startsWith(':')) {
      final colon = line.indexOf(':');
      final key = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      if (key == 'event') event = value;
      if (key == 'id') id = value;
      if (key == 'data') data.add(value);
    }
  }
  if (data.isNotEmpty) throw const FormatException('incomplete SSE frame');
}
