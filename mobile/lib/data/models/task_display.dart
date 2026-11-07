/// Shared labels for the tag IDs submitted by the task dispatch form.
const taskTagLabels = <String, String>{
  'company-important': '重要',
  'department-research': '研发',
  'department-design': '设计',
  'personal-today': '今日',
};

/// Completion is a projection of the server lifecycle, never a date estimate.
/// A returned result goes back to RECEIVED; RETURNED itself is an event.
const taskCompletionLabels = <String, String>{
  'DISPATCHED': '待接收',
  'RECEIVED': '进行中',
  'FEEDBACK': '待验收',
  'ACCEPTED': '已验收',
  'ARCHIVED': '已归档',
  'WITHDRAWN': '已撤回',
};

String taskCompletionLabel(Map<String, dynamic> fields) {
  final phase = fields['phase'];
  if (fields.containsKey('phase')) {
    return taskCompletionLabels['$phase'] ?? '情况未知';
  }
  // Older local fixtures contain the explicit lifecycle label instead of phase.
  final status = '${fields['status'] ?? ''}';
  return taskCompletionLabels[status] ??
      (taskCompletionLabels.containsValue(status) ? status : '情况未知');
}

String taskTagLabel(Map<String, dynamic> fields) {
  final labels = fields['labels'];
  if (labels is List) {
    final names = labels
        .whereType<Map>()
        .map((label) => '${label['name'] ?? label['title'] ?? ''}'.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isNotEmpty) return names.join('、');
  }
  final id = '${fields['tagId'] ?? fields['tag_id'] ?? fields['标签'] ?? ''}'
      .trim();
  final label = '${fields['tagName'] ?? fields['tag_name'] ?? ''}'.trim();
  if (label.isNotEmpty && label != id && label != '标签名称未提供') {
    return label;
  }
  return taskTagLabels[id] ??
      (id == 'customer-delivery'
          ? '客户交付'
          : id.isEmpty
          ? '未分类'
          : '标签名称未提供');
}

/// Forward-compatible display for optional multi-label responses; legacy label remains valid.
List<String> taskTagNames(Map<String, dynamic> fields) {
  final labels = fields['labels'];
  if (labels is List) {
    return labels
        .whereType<Map>()
        .map((label) => '${label['name'] ?? label['title'] ?? ''}'.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }
  return [taskTagLabel(fields)];
}

/// Names are display data, never a substitute for participant IDs or authority.
List<String> taskParticipantNames(
  Map<String, dynamic> fields, {
  Map<String, String> namesById = const {},
}) {
  final rawIds = fields['participantIds'] ?? fields['participant_ids'];
  final rawNames = fields['participantNames'] ?? fields['participant_names'];
  final ids = rawIds is List
      ? rawIds.map((value) => '${value ?? ''}'.trim()).toList()
      : const <String>[];
  final names = rawNames is List
      ? rawNames.map((value) => '${value ?? ''}'.trim()).toList()
      : const <String>[];
  if (ids.isEmpty) return names.where((name) => name.isNotEmpty).toList();
  return [
    for (var i = 0; i < ids.length; i++)
      if (ids[i].isNotEmpty)
        if (namesById[ids[i]]?.trim().isNotEmpty ?? false)
          namesById[ids[i]]!.trim()
        else if (i < names.length &&
            names[i].isNotEmpty &&
            !ids.contains(names[i]))
          names[i]
        else
          '成员姓名未提供',
  ];
}
