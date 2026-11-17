import '../../../shared/widgets.dart' show notice, NoticeTone;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/state/providers.dart';
import '../../../data/models/models.dart';
import '../../../shared/calendar/civil_date.dart';
import '../../calendar/calendar_data_source.dart';
import '../../calendar/calendar_schedule.dart';
import '../application/todo_providers.dart';
import '../data/personal_todo.dart';
import 'todo_editor.dart';

final todoCalendarDateProvider = StateProvider<DateTime>((ref) {
  ref.watch(sessionProvider.select((s) => (s.id, s.token)));
  return shanghaiToday();
});

Record todoCalendarRecord(PersonalTodo todo, String ownerId) => Record(
  id: todo.id,
  title: todo.title,
  subtitle: todo.note,
  ownerId: ownerId,
  version: todo.version,
  fields: {
    'startAt': '${todo.date}T00:00:00+08:00',
    'deadline': '${todo.lastDate}T23:59:59+08:00',
    'tagColor': todo.color,
    'capabilities': {'reschedule': true},
  },
);

final todoCalendarRecordsProvider = FutureProvider.autoDispose
    .family<PageResult, String>((ref, month) async {
      final repo = ref.watch(todoRepositoryProvider);
      final account = ref.watch(sessionProvider);
      var active = true;
      ref.onDispose(() => active = false);
      // Offset pagination is checked as a complete set; one restart handles a
      // concurrent write without silently presenting a partial month as complete.
      for (var attempt = 0; attempt < 2; attempt++) {
        final rows = <String, PersonalTodo>{};
        final cursors = <String>{};
        String? cursor = '0';
        int? total;
        var inconsistent = false;
        while (cursor != null && active) {
          if (!cursors.add(cursor)) {
            inconsistent = true;
            break;
          }
          final page = await repo.month(month, cursor);
          if (!active) {
            throw const ApiFailure(FailureKind.unavailable, '事项读取已取消');
          }
          total ??= page.total;
          if (total != page.total ||
              page.items.any((t) => rows.containsKey(t.id)) ||
              (page.nextCursor != null && page.items.isEmpty)) {
            inconsistent = true;
            break;
          }
          for (final todo in page.items) {
            rows[todo.id] = todo;
          }
          cursor = page.nextCursor;
        }
        if (!inconsistent && cursor == null && rows.length == total) {
          return PageResult(
            rows.values.map((t) => todoCalendarRecord(t, account.id)).toList(),
            total: rows.length,
            scheduleConstraints: {
              'zone': 'Asia/Shanghai',
              'minDate': '1900-01-01',
              'maxDate': '2100-12-31',
              'revision': 'calendar-v1-2026',
            },
          );
        }
      }
      throw const ApiFailure(FailureKind.conflict, '事项列表已变化，请刷新后重试');
    });

class TodoCalendarSource extends CalendarDataSource {
  const TodoCalendarSource();
  @override
  int get firstYear => 1900;
  @override
  int get lastYear => 2100;
  String _month(DateTime day) => civilDate(day).substring(0, 7);
  @override
  AutoDisposeFutureProvider<PageResult> monthProvider(DateTime month) =>
      todoCalendarRecordsProvider(_month(month));
  @override
  void invalidateMonth(WidgetRef ref, DateTime month) =>
      ref.invalidate(todoCalendarRecordsProvider(_month(month)));
  @override
  void refresh(WidgetRef ref) {
    ref.invalidate(todoCalendarRecordsProvider);
    ref.invalidate(todoMonthProvider);
    ref.invalidate(todoDayProvider);
  }

  @override
  Future<Record> detail(WidgetRef ref, String id) async {
    final account = ref.read(sessionProvider);
    final todo = await ref.read(todoRepositoryProvider).detail(id);
    return todoCalendarRecord(todo, account.id);
  }

  bool _current(WidgetRef ref, Session account) =>
      ref.context.mounted &&
      ref.read(sessionProvider).id == account.id &&
      ref.read(sessionProvider).token == account.token;
  @override
  Future<void> saveMove(
    WidgetRef ref,
    Record record,
    CalendarSchedule after,
  ) async {
    if (ref.read(pendingTodoCommandProvider) != null) {
      throw const ApiFailure(FailureKind.conflict, '上一条事项保存结果待确认，请打开事项编辑器继续确认');
    }
    final account = ref.read(sessionProvider);
    final repo = ref.read(todoRepositoryProvider);
    final latest = await repo.detail(record.id);
    if (!_current(ref, account)) return;
    if (latest.version != record.version) {
      throw const ApiFailure(FailureKind.conflict, '事项已有新版本，请刷新后重试');
    }
    final command = TodoCommand('PUT', record.id, {
      ...latest.editBody,
      'date': civilDate(scheduleWallTime(after.start!)),
      'endDate': civilDate(scheduleWallTime(after.end)),
    });
    ref.read(pendingTodoCommandProvider.notifier).state = command;
    try {
      await repo.execute(command);
      if (_current(ref, account)) {
        ref.read(pendingTodoCommandProvider.notifier).state = null;
      }
    } on ApiFailure catch (e) {
      if (_current(ref, account) &&
          const [
            FailureKind.validation,
            FailureKind.forbidden,
            FailureKind.notFound,
            FailureKind.conflict,
          ].contains(e.kind)) {
        ref.read(pendingTodoCommandProvider.notifier).state = null;
      }
      rethrow;
    }
  }

  @override
  Future<void> create(BuildContext context, WidgetRef ref, DateTime day) async {
    await showTodoEditor(context, date: civilDate(day));
  }

  @override
  Future<void> open(BuildContext context, WidgetRef ref, Record record) async {
    final account = ref.read(sessionProvider);
    try {
      final todo = await ref.read(todoRepositoryProvider).detail(record.id);
      if (!context.mounted || !_current(ref, account)) return;
      await showTodoEditor(context, date: todo.date, todo: todo);
    } catch (e) {
      if (context.mounted) {
        notice(context, '$e', tone: NoticeTone.error);
      }
    }
  }
}
