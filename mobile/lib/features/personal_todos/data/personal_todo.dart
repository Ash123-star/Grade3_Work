import 'dart:convert';
import 'dart:math';
import '../../../shared/calendar/civil_date.dart';

class PersonalTodo {
  const PersonalTodo({
    required this.id,
    required this.title,
    required this.note,
    required this.date,
    this.endDate = '',
    this.color = defaultColor,
    required this.completed,
    required this.version,
  });
  static const defaultColor = '#F3A45D';
  final String id, title, note, date, endDate, color;
  final bool completed;
  final int version;
  String get lastDate => endDate.isEmpty ? date : endDate;
  factory PersonalTodo.fromJson(Map<String, dynamic> json) {
    final date = json['date'] as String;
    parseCivilDate(date);
    final endDate = (json['endDate'] as String?) ?? date;
    parseCivilDate(endDate);
    if (endDate.compareTo(date) < 0) throw const FormatException('无效事项日期范围');
    final color = (json['color'] as String?) ?? defaultColor;
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
      throw const FormatException('无效事项颜色');
    }
    final version = json['version'] as int;
    if (version < 1 || (json['id'] as String).isEmpty) {
      throw const FormatException('无效事项');
    }
    return PersonalTodo(
      id: json['id'] as String,
      title: json['title'] as String,
      note: json['note'] as String,
      date: date,
      endDate: endDate,
      color: color.toUpperCase(),
      completed: json['completed'] as bool,
      version: version,
    );
  }
  Map<String, dynamic> get editBody => {
    'title': title,
    'note': note,
    'date': date,
    'endDate': lastDate,
    'color': color,
    'completed': completed,
    'version': version,
  };
}

class TodoPage {
  const TodoPage(this.items, this.total, this.nextCursor);
  final List<PersonalTodo> items;
  final int total;
  final String? nextCursor;
}

class TodoCount {
  const TodoCount(this.total, this.completed);
  final int total, completed;
  int get pending => total - completed;
}

/// An immutable request, retained for uncertain outcomes. Retrying never changes its key/body.
class TodoCommand {
  TodoCommand(this.method, this.id, Map<String, dynamic> body)
    : body = Map.unmodifiable(body),
      key = List.generate(
        24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
  final String method, key;
  final String? id;
  final Map<String, dynamic> body;
  String get signature => jsonEncode([method, id, body]);
}
