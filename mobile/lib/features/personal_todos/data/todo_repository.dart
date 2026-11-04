import 'package:dio/dio.dart';
import '../../../core/errors/api_failure.dart';
import '../../../shared/calendar/civil_date.dart';
import 'personal_todo.dart';

abstract interface class TodoRepository {
  Future<Map<String, TodoCount>> calendar(String month);
  Future<TodoPage> day(String date, String cursor);
  Future<PersonalTodo> detail(String id);
  Future<void> execute(TodoCommand command);
}

class HttpTodoRepository implements TodoRepository {
  HttpTodoRepository(this.dio);
  final Dio dio;
  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    } on FormatException {
      throw const ApiFailure(FailureKind.server, '事项响应格式不完整，请重试');
    } on TypeError {
      throw const ApiFailure(FailureKind.server, '事项响应格式不完整，请重试');
    }
  }

  @override
  Future<Map<String, TodoCount>> calendar(String month) => _guard(() async {
    final response = await dio.get<Map<String, dynamic>>(
      '/personal-todos/calendar',
      queryParameters: {'month': month},
    );
    final body = response.data!;
    if (body['month'] != month) throw const FormatException('月份不匹配');
    final days = body['days'] as List;
    final expected = monthDays(
      parseCivilDate('$month-01'),
    ).map(civilDate).toSet();
    final result = <String, TodoCount>{};
    for (final raw in days) {
      final item = Map<String, dynamic>.from(raw as Map);
      final date = item['date'] as String;
      final total = item['total'] as int, completed = item['completed'] as int;
      if (!expected.contains(date) ||
          result.containsKey(date) ||
          total < 0 ||
          completed < 0 ||
          completed > total) {
        throw const FormatException('无效计数');
      }
      result[date] = TodoCount(total, completed);
    }
    if (result.length != expected.length) throw const FormatException('月历不完整');
    return result;
  });
  @override
  Future<TodoPage> day(String date, String cursor) => _guard(() async {
    final response = await dio.get<Map<String, dynamic>>(
      '/personal-todos',
      queryParameters: {'date': date, 'cursor': cursor, 'limit': 30},
    );
    final body = response.data!;
    final items = (body['items'] as List)
        .map((r) => PersonalTodo.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    final total = body['total'] as int;
    final next = body['nextCursor'] as String?;
    if (total < 0 ||
        items.any((t) => t.date != date) ||
        (next != null &&
            (int.tryParse(next) == null ||
                int.parse(next) <= int.parse(cursor)))) {
      throw const FormatException('无效事项分页');
    }
    return TodoPage(items, total, next);
  });
  @override
  Future<PersonalTodo> detail(String id) => _guard(() async {
    final response = await dio.get<Map<String, dynamic>>(
      '/personal-todos/${Uri.encodeComponent(id)}',
    );
    final todo = PersonalTodo.fromJson(response.data!);
    if (todo.id != id) throw const FormatException('事项不匹配');
    return todo;
  });
  @override
  Future<void> execute(TodoCommand command) => _guard(() async {
    final response = await dio.request<Map<String, dynamic>>(
      '/personal-todos${command.id == null ? '' : '/${Uri.encodeComponent(command.id!)}'}',
      data: command.method == 'DELETE' ? null : command.body,
      queryParameters: command.method == 'DELETE' ? command.body : null,
      options: Options(
        method: command.method,
        headers: {'Idempotency-Key': command.key},
      ),
    );
    if (command.method == 'DELETE') {
      if (response.data?['id'] != command.id ||
          response.data?['deleted'] != true ||
          response.data?['version'] != (command.body['version'] as int) + 1) {
        throw const FormatException('删除尚未确认');
      }
    } else {
      final result = PersonalTodo.fromJson(response.data!);
      if ((command.id != null && result.id != command.id) ||
          result.version !=
              (command.method == 'POST'
                  ? 1
                  : (command.body['version'] as int) + 1)) {
        throw const FormatException('事项保存尚未确认');
      }
    }
  });
}

/// Explicit in-memory demo only. Production uses HttpTodoRepository exclusively.
class DemoTodoRepository implements TodoRepository {
  final _items = <String, PersonalTodo>{};
  final _receipts = <String, String>{};
  @override
  Future<Map<String, TodoCount>> calendar(String month) async => {
    for (final day in monthDays(parseCivilDate('$month-01')))
      civilDate(day): TodoCount(
        _items.values.where((t) => t.date == civilDate(day)).length,
        _items.values
            .where((t) => t.date == civilDate(day) && t.completed)
            .length,
      ),
  };
  @override
  Future<TodoPage> day(String date, String cursor) async {
    final rows = _items.values.where((t) => t.date == date).toList()
      ..sort(
        (a, b) => a.completed == b.completed
            ? a.id.compareTo(b.id)
            : a.completed
            ? 1
            : -1,
      );
    final offset = int.parse(cursor),
        items = rows.skip(offset).take(30).toList();
    return TodoPage(
      items,
      rows.length,
      offset + items.length < rows.length ? '${offset + items.length}' : null,
    );
  }

  @override
  Future<PersonalTodo> detail(String id) async {
    if (!_items.containsKey(id)) {
      throw const ApiFailure(FailureKind.notFound, '事项已删除');
    }
    return _items[id]!;
  }

  @override
  Future<void> execute(TodoCommand c) async {
    if (_receipts.containsKey(c.key)) {
      if (_receipts[c.key] != c.signature) {
        throw const ApiFailure(FailureKind.conflict, '幂等键已被使用');
      }
      return;
    }
    final old = c.id == null ? null : await detail(c.id!);
    if (old != null && old.version != c.body['version']) {
      throw const ApiFailure(
        FailureKind.conflict,
        '内容已有新版本',
        code: 'VERSION_CONFLICT',
      );
    }
    if (c.method == 'DELETE') {
      _items.remove(c.id);
    } else {
      final id = c.id ?? c.key;
      _items[id] = PersonalTodo.fromJson({
        ...c.body,
        'id': id,
        'note': c.body['note'] ?? '',
        'completed': c.body['completed'] ?? false,
        'version': (old?.version ?? 0) + 1,
      });
    }
    _receipts[c.key] = c.signature;
  }
}
