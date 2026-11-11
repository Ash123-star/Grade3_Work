import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/personal_todos/data/personal_todo.dart';
import 'package:pandora_mobile/features/personal_todos/data/todo_repository.dart';

void main() {
  test('multi-day todo keeps range and colour across day pages', () async {
    final repo = DemoTodoRepository();
    await repo.execute(
      TodoCommand('POST', null, {
        'title': '跨天事项',
        'date': '2026-11-08',
        'endDate': '2026-11-10',
        'color': '#8FC7B0',
        'note': '',
      }),
    );
    final day = await repo.day('2026-11-09', '0');
    expect(day.items.single.title, '跨天事项');
    expect(day.items.single.endDate, '2026-11-10');
    expect(day.items.single.lastDate, '2026-11-10');
    expect(day.items.single.color, '#8FC7B0');
    final month = await repo.calendar('2026-11');
    expect(month['2026-11-08']!.total, 1);
    expect(month['2026-11-09']!.total, 1);
    expect(month['2026-11-10']!.total, 1);
    expect(month['2026-11-11']!.total, 0);
    expect((await repo.day('2026-11-11', '0')).items, isEmpty);
  });

  test('todo JSON defaults a missing range to its single date and colour', () {
    final todo = PersonalTodo.fromJson({
      'id': 'todo-1',
      'title': '单日事项',
      'note': '',
      'date': '2026-11-08',
      'completed': false,
      'version': 1,
    });
    expect(todo.endDate, '2026-11-08');
    expect(todo.lastDate, '2026-11-08');
    expect(todo.color, PersonalTodo.defaultColor);
  });
}
