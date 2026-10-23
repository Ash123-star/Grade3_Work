class WorkListPage {
  const WorkListPage(this.items, this.nextCursor);
  factory WorkListPage.fromJson(Object? value) {
    final json = _contract(value);
    final cursor = _integer(json['nextCursor'], minimum: -1);
    return WorkListPage(
      List.unmodifiable(
        _objects(json['items']).map((e) => WorkItem.fromJson(e, summary: true)),
      ),
      cursor,
    );
  }
  final List<WorkItem> items;
  final int nextCursor;
}

class WorkCapabilities {
  const WorkCapabilities({
    required this.enabled,
    required this.configured,
    this.limits = const {},
  });
  factory WorkCapabilities.fromJson(Object? value) {
    final json = _contract(value);
    for (final field in [
      'enabled',
      'configured',
      'executionEnabled',
      'imageEnabled',
      'canCreateTask',
    ]) {
      if (json[field] is! bool) {
        throw const FormatException('Invalid capability');
      }
    }
    _strings(json['actions']);
    final limits = _object(json['limits']);
    for (final field in ['text', 'files', 'fileBytes', 'totalBytes']) {
      _integer(limits[field], minimum: 1);
    }
    _strings(limits['formats']);
    return WorkCapabilities(
      enabled: json['enabled'] as bool,
      configured: json['configured'] as bool,
      limits: _freeze(limits) as Map<String, dynamic>,
    );
  }
  final bool enabled, configured;
  final Map<String, dynamic> limits;
}

class WorkItem {
  const WorkItem(this.json);

  /// REST边界拒绝损坏/不兼容的记录，不用默认成功替代未知结果。
  factory WorkItem.fromJson(Object? value, {bool summary = false, String? id}) {
    final json = summary ? _object(value) : _contract(value);
    _text(json['id']);
    if (id != null && json['id'] != id) {
      throw const FormatException('Mismatched work identity');
    }
    _text(json['title']);
    _integer(json['version'], minimum: 1);
    if (!states.contains(json['state'])) {
      throw const FormatException('Unknown work state');
    }
    _integer(json['planVersion'] ?? json['plan_version'], minimum: 0);
    _object(json['result']);
    if (!summary) {
      _integer(json['eventsCursor'], minimum: 0);
      for (final message in _objects(json['messages'])) {
        final body = _object(message['body']);
        _text(body['text'], allowEmpty: true);
        _strings(body['attachmentIds']);
      }
      for (final receipt in _objects(json['receipts'])) {
        _text(receipt['step_key']);
        final result = _object(receipt['result']);
        if (result['report'] != null) {
          _objects(_object(result['report'])['findings']);
        }
      }
      for (final step in _objects(json['steps'])) {
        _text(step['step_key']);
        _text(step['state']);
      }
      if (json['planValid'] != null && json['planValid'] is! bool) {
        throw const FormatException('Invalid plan validity');
      }
      if (json['plan'] != null) {
        final plan = _object(json['plan']);
        if (plan['questions'] != null) _strings(plan['questions']);
        for (final field in ['people', 'sources', 'actions']) {
          if (plan[field] != null) _objects(plan[field]);
        }
        for (final action in workMaps(plan['actions'])) {
          _object(action['payload']);
          if (action['similarTasks'] != null) _objects(action['similarTasks']);
        }
      }
    }
    return WorkItem(_freeze(json) as Map<String, dynamic>);
  }
  static const states = {
    'QUEUED',
    'PREPARING',
    'READY',
    'EXECUTING',
    'SUCCEEDED',
    'WAITING_INPUT',
    'WAITING_CONFIRMATION',
    'WAITING_REVIEW',
    'PARTIAL',
    'FAILED',
    'RECONCILING',
    'CANCEL_REQUESTED',
    'CANCELLED',
  };
  final Map<String, dynamic> json;
  String get id => '${json['id'] ?? ''}';
  String get title => '${json['title'] ?? '新的事项'}';
  String get state => '${json['state'] ?? 'QUEUED'}';
  int get version => (json['version'] as num?)?.toInt() ?? 1;
  int get planVersion =>
      ((json['planVersion'] ?? json['plan_version']) as num?)?.toInt() ?? 0;
  Map<String, dynamic> get result => workMap(json['result']);
  Map<String, dynamic> get plan => workMap(json['plan']);
  List<Map<String, dynamic>> get messages => workMaps(json['messages']);
  List<Map<String, dynamic>> get receipts => workMaps(json['receipts']);
  List<Map<String, dynamic>> get actions => workMaps(plan['actions']);
  List<String> get questions =>
      (plan['questions'] as List? ?? []).map((e) => '$e').toList();
  bool get processing => [
    'QUEUED',
    'PREPARING',
    'READY',
    'EXECUTING',
    'RECONCILING',
    'CANCEL_REQUESTED',
  ].contains(state);
  String get label => switch (state) {
    'QUEUED' || 'PREPARING' => '正在整理',
    'READY' => '准备办理',
    'EXECUTING' => '正在办理',
    'RECONCILING' => '正在核对结果',
    'WAITING_INPUT' => '需要补充',
    'WAITING_CONFIRMATION' => '请你核对',
    'WAITING_REVIEW' => '等待复核',
    'PARTIAL' => '还有事项待处理',
    'FAILED' => '暂时未能处理',
    'CANCEL_REQUESTED' => '正在停止',
    'CANCELLED' => '已停止',
    'SUCCEEDED' => _completedLabel,
    _ => '状态暂时无法确认',
  };
  String get _completedLabel {
    final report = workMap(result['report']);
    return switch ('${report['state'] ?? ''}') {
      'NEEDS_FIX' => '需要补充材料',
      'UNVERIFIABLE' => '有些内容需核对',
      'STALE' => '需要重新检查',
      'PASS' => '材料已核对',
      _ => switch (result['kind']) {
        'TASK_CREATED' => '任务已创建',
        _ => result['summary'] == '已提交，等待验收' ? '已提交反馈' : '已处理',
      },
    };
  }
}

Map<String, dynamic> _contract(Object? value) {
  final json = _object(value);
  if (json['contractVersion'] != 1) {
    throw const FormatException('Unsupported work contract');
  }
  return json;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected work object');
  }
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _objects(Object? value) {
  if (value is! List) throw const FormatException('Expected work array');
  return value.map(_object).toList();
}

void _strings(Object? value) {
  if (value is! List || value.any((e) => e is! String)) {
    throw const FormatException('Expected work text array');
  }
}

void _text(Object? value, {bool allowEmpty = false}) {
  if (value is! String || !allowEmpty && value.trim().isEmpty) {
    throw const FormatException('Expected work text');
  }
}

int _integer(Object? value, {required int minimum}) {
  if (value is! int || value < minimum) {
    throw const FormatException('Expected work version or cursor');
  }
  return value;
}

Object? _freeze(Object? value) => switch (value) {
  Map() => Map<String, dynamic>.unmodifiable(
    value.map((key, item) => MapEntry(key as String, _freeze(item))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};

Map<String, dynamic> workMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> workMaps(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];

String workDate(Object? value) {
  final parsed = DateTime.tryParse('$value');
  if (parsed == null) return '请核对截止时间';
  final date = parsed.toUtc().add(const Duration(hours: 8));
  return '${date.year}年${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
