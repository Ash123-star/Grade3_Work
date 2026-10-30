/// Presentation names must never fall back to login accounts or internal IDs.
String displayPersonName(Object? name) {
  final text = name is String ? name.trim() : '';
  return text.isEmpty ? '未知成员' : text;
}

/// Logs have one work field rather than a separate editable title.
String workLogTitle(Map<String, dynamic> fields, {Object? explicitTitle}) {
  final title = explicitTitle is String ? explicitTitle.trim() : '';
  if (title.isNotEmpty) return title;
  final content = '${fields['work'] ?? fields['今日工作'] ?? ''}';
  for (final line in content.split(RegExp(r'[\r\n]+'))) {
    final text = line
        .replaceFirst(RegExp(r'^\s*(?:[-*•]\s+|\d+[.、)）]\s*)'), '')
        .trim();
    if (text.isEmpty) continue;
    final characters = text.runes.toList();
    return characters.length > 48
        ? '${String.fromCharCodes(characters.take(48))}…'
        : text;
  }
  return '工作日志';
}
