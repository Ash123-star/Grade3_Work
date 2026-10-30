import 'models.dart';

const _labels = <String, String>{
  'title': '标题',
  'name': '名称',
  'content': '内容',
  'text': '说明',
  'work': '工作内容',
  'blockers': '遇到的阻碍',
  'tomorrow': '后续计划',
  'hours': '工时',
  'reason': '申请原因',
  'group': '分组',
  'startAt': '开始时间',
  'start_at': '开始时间',
  'deadline': '截止时间',
  'urgency': '紧急程度',
  'phase': '任务状态',
  'status': '状态',
  'role': '角色',
  'labelId': '任务标签',
  'label_id': '任务标签',
  'tagId': '任务标签',
  'tag_id': '任务标签',
  'participants': '参与人',
  'participantIds': '参与人',
  'participant_ids': '参与人',
  'ownerId': '负责人',
  'owner_id': '负责人',
  'collaborators': '协作人',
  'managerId': '直属上级',
  'manager_id': '直属上级',
  'departmentId': '部门',
  'department_id': '部门',
  'teamId': '团队',
  'team_id': '团队',
  'attachments': '附件',
  'acceptanceChecklist': '验收清单',
  'dispatchEnabled': '任务派发权限',
  'companyReviewer': '成员确认权限',
  'required': '是否必需',
  'description': '说明',
  'aiWorkCreateAuthorization': '允许授权创建任务',
  'aiWorkSubmitAuthorization': '允许授权提交成果',
  'aiWorkAuthorizationMaxDays': '授权最长天数',
  'aiWorkAuthorizationMaxObjects': '授权最多对象数',
  'aiWorkAuthorizationMaxActions': '每批最多动作数',
};

const _enums = <String, String>{
  'NORMAL': '普通',
  'URGENT': '紧急',
  'LOW': '不紧急',
  'ADMIN': '管理员',
  'FOUNDER': '创始人',
  'DIRECTOR': '部门老总',
  'LEADER': '团队长',
  'EMPLOYEE': '员工',
  'ACTIVE': '正常',
  'PENDING': '待确认',
  'DISABLED': '已停用',
  'APPROVED': '已通过',
  'REJECTED': '已驳回',
  'SUPERSEDED': '已失效',
  'DISPATCHED': '待接收',
  'RECEIVED': '进行中',
  'FEEDBACK': '待验收',
  'ACCEPTED': '已验收',
  'ARCHIVED': '已归档',
  'WITHDRAWN': '已撤回',
};

String reviewSnapshotText(Object? snapshot, Object? references) {
  if (snapshot == null) return '无内容';
  if (snapshot is! Map) return '$snapshot'.trim().isEmpty ? '无内容' : '$snapshot';
  if (snapshot.isEmpty) return '无内容';
  final refs = references is Map ? references : const {};
  final lines = <String>[];
  var other = false;
  for (final entry in snapshot.entries) {
    final key = '${entry.key}';
    if (['body', 'summary', 'fields'].contains(key) && entry.value is Map) {
      lines.add(reviewSnapshotText(entry.value, refs));
      continue;
    }
    // Internal metadata does not belong to the business comparison.
    if ([
      'id',
      'version',
      'created_at',
      'updated_at',
      'company_id',
      'issuer_id',
      'deleted',
      'deleted_at',
    ].contains(key)) {
      continue;
    }
    final label = _labels[key];
    if (label == null) {
      other = true;
      continue;
    }
    final value = entry.value;
    String display;
    final category = switch (key) {
      'labelId' || 'label_id' || 'tagId' || 'tag_id' => 'labels',
      'participants' ||
      'participantIds' ||
      'participant_ids' ||
      'ownerId' ||
      'owner_id' ||
      'managerId' ||
      'manager_id' ||
      'collaborators' => 'people',
      'departmentId' || 'department_id' => 'departments',
      'teamId' || 'team_id' => 'teams',
      _ => null,
    };
    if (category != null) {
      final names = refs[category] is Map ? refs[category] as Map : const {};
      final ids = value is List ? value : [value];
      final resolved = [
        for (final id in ids)
          if (id != null && '$id'.trim().isNotEmpty)
            '${names['$id'] ?? '名称暂不可用'}',
      ];
      display = resolved.isEmpty ? '未设置' : resolved.join('、');
    } else if (key == 'attachments') {
      display = value is List && value.isNotEmpty
          ? '${value.length} 个附件'
          : '无附件';
    } else if (['startAt', 'start_at', 'deadline'].contains(key)) {
      final date = businessEventTime(value);
      display = date == null
          ? '未设置'
          : '${date.year}年${date.month}月${date.day}日 '
                '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (value is bool) {
      display = value ? '是' : '否';
    } else if (value is Map) {
      display = reviewSnapshotText(value, refs);
    } else if (value is List) {
      display = value.isEmpty
          ? '无'
          : value
                .map((v) => v is Map ? reviewSnapshotText(v, refs) : '$v')
                .join('\n');
    } else if (value == null || '$value'.trim().isEmpty) {
      display = '未设置';
    } else if (['urgency', 'phase', 'status', 'role'].contains(key)) {
      display = _enums['$value'] ?? '状态暂不可用';
    } else {
      display = '$value';
    }
    lines.add('$label：$display');
  }
  if (other) lines.add('其他设置：已记录变更');
  return lines.isEmpty ? '无内容' : lines.join('\n');
}
