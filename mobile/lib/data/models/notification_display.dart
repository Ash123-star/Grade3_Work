/// Notification protocol codes stay unchanged; only presentation is localized.
String notificationCategory(Object? type) => switch (type) {
  'TASK_COMMENT' || 'LOG_COMMENT' => '评论',
  'DEADLINE' => '截止提醒',
  'REVIEW_APPROVED' || 'REVIEW_REJECTED' => '审核结果',
  'REVIEW_PENDING' || 'REVIEW_UNASSIGNED' => '审批',
  'LOG_SUBMITTED' || 'LOG_UPDATED' => '待阅提醒',
  'TASK_DISPATCHED' ||
  'TASK_ASSIGNED' ||
  'TASK_EVENT' ||
  'TASK_REVISED' ||
  'TASK_REASSIGNED' ||
  'TASK_RESCHEDULED' ||
  'DELIVERY_CHECKED' => '任务',
  _ => '其他',
};

String notificationDisplayTitle(Object? title, Object? type) {
  final text = title is String ? title.trim() : '';
  return text.isEmpty || RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(text)
      ? notificationTitle(type)
      : text;
}

String notificationTitle(Object? type) => switch (type) {
  'TASK_DISPATCHED' || 'TASK_ASSIGNED' => '收到新任务',
  'TASK_EVENT' => '任务进度更新',
  'TASK_REVISED' => '任务内容已更新',
  'TASK_REASSIGNED' => '任务参与安排已调整',
  'TASK_RESCHEDULED' => '任务截止时间已调整',
  'TASK_COMMENT' => '任务新评论',
  'DEADLINE' => '任务截止提醒',
  'LOG_SUBMITTED' => '收到工作日志',
  'LOG_UPDATED' => '工作日志已更新',
  'LOG_COMMENT' => '日志新评论',
  'REVIEW_PENDING' => '有申请待审核',
  'REVIEW_APPROVED' => '申请已通过',
  'REVIEW_REJECTED' => '申请已驳回',
  'REVIEW_UNASSIGNED' => '有申请缺少审核人',
  'AI_READY' => 'AI 分析已完成',
  'AI_WORK_UPDATED' => 'AI 工作状态更新',
  'DELIVERY_CHECKED' => '任务交付检查已完成',
  _ => '工作通知',
};

String? notificationResource(Object? type) => switch (type) {
  'TASK_DISPATCHED' ||
  'TASK_ASSIGNED' ||
  'TASK_EVENT' ||
  'TASK_REVISED' ||
  'TASK_REASSIGNED' ||
  'TASK_RESCHEDULED' ||
  'TASK_COMMENT' ||
  'DEADLINE' ||
  'DELIVERY_CHECKED' => 'tasks',
  'LOG_SUBMITTED' || 'LOG_UPDATED' || 'LOG_COMMENT' => 'logs',
  'REVIEW_PENDING' ||
  'REVIEW_APPROVED' ||
  'REVIEW_REJECTED' ||
  'REVIEW_UNASSIGNED' => 'reviews',
  'AI_READY' => 'ai-jobs',
  'AI_WORK_UPDATED' => 'ai-work',
  _ => null,
};
