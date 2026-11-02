/// Shared labels for the tag IDs submitted by the task dispatch form.
const taskTagLabels = <String, String>{
  'company-important': '重要',
  'department-research': '研发',
  'department-design': '设计',
  'personal-today': '今日',
};

String taskTagLabel(Map<String, dynamic> fields) {
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
