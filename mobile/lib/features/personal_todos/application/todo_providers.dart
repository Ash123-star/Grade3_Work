import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/state/providers.dart';
import '../data/personal_todo.dart';
import '../data/todo_repository.dart';

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  final session = ref.watch(
    sessionProvider.select((s) => (s.id, s.token, s.canReadBusiness)),
  );
  if (!session.$3) throw const ApiFailure(FailureKind.forbidden, '请先确认账号权限');
  return AppConfig.mock
      ? DemoTodoRepository()
      : HttpTodoRepository(ref.watch(httpRepositoryProvider).dio);
});
final todoMonthProvider = FutureProvider.autoDispose
    .family<Map<String, TodoCount>, String>(
      (ref, month) => ref.watch(todoRepositoryProvider).calendar(month),
    );
final todoDayProvider = FutureProvider.autoDispose
    .family<TodoPage, (String, String)>(
      (ref, key) => ref.watch(todoRepositoryProvider).day(key.$1, key.$2),
    );

/// Retain an uncertain request across closing/reopening the editor within this session.
final pendingTodoCommandProvider = StateProvider<TodoCommand?>((ref) {
  ref.watch(sessionProvider.select((s) => (s.id, s.token, s.canReadBusiness)));
  return null;
});
