import 'package:pandora_mobile/core/errors/api_failure.dart';

Map<String, dynamic> aiObject(dynamic value) {
  if (value is! Map) throw const ApiFailure(FailureKind.server, '分析数据格式不完整');
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> aiObjects(dynamic value, {int max = 100}) {
  if (value is! List || value.length > max) {
    throw const ApiFailure(FailureKind.server, '分析数据格式不完整');
  }
  return value.map(aiObject).toList();
}

List<String> aiIds(dynamic value) =>
    value is List && value.every((e) => e is String)
    ? List<String>.from(value)
    : <String>[];

class AiSource {
  AiSource(this.data);
  final Map<String, dynamic> data;
  String get id => '${data['id'] ?? ''}';
  String get owner => '${data['ownerId'] ?? ''}';
  String get title =>
      '${data['title'] ?? (id.startsWith('log:') ? '${data['date'] ?? ''} 工作日志' : '个人重点')}';
  bool get overdue => data['overdue'] == true;
  String? route(String account) {
    final uri = Uri.tryParse('${data['url'] ?? ''}');
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final parts = id.split(':');
    if (parts.length != 2 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts[1])) {
      return null;
    }
    final object = Uri.encodeComponent(parts[1]);
    if (parts[0] == 'task' &&
        uri.path == '/api/tasks/${parts[1]}' &&
        !uri.hasQuery) {
      return '/item/tasks/$object';
    }
    if (parts[0] == 'log' &&
        uri.path == '/api/logs/${parts[1]}' &&
        !uri.hasQuery) {
      return '/item/logs/$object';
    }
    if (parts[0] == 'item' &&
        uri.path == '/api/dashboard/personal' &&
        uri.queryParameters.length == 1 &&
        uri.queryParameters['ownerId'] == account) {
      return '/item/dashboard%2Fpersonal/$object?ownerId=${Uri.encodeComponent(account)}';
    }
    return null;
  }
}

class AiJob {
  AiJob._(this.data, this.input, this.output, this.sources);
  final Map<String, dynamic> data, input;
  final Map<String, dynamic>? output;
  final List<AiSource> sources;
  factory AiJob.fromJson(dynamic value) {
    final data = aiObject(value), input = aiObject(data['input']);
    if (data['id'] is! String ||
        '${data['id']}'.isEmpty ||
        data['version'] is! num ||
        ![
          'QUEUED',
          'RUNNING',
          'SUCCEEDED',
          'FAILED',
          'CANCELLED',
        ].contains(data['state'])) {
      throw const ApiFailure(FailureKind.server, '分析作业状态不完整，请刷新');
    }
    final sources = aiObjects(
      input['sources'],
      max: 110,
    ).map(AiSource.new).toList();
    final output = data['output'] == null ? null : aiObject(data['output']);
    if (output != null) {
      aiObjects(output['nodes'], max: 10);
      aiObjects(output['actions'], max: 3);
      if (output['summary'] is! String) {
        throw const ApiFailure(FailureKind.server, '分析正文未提供');
      }
    }
    if (data['state'] == 'SUCCEEDED' && output == null) {
      throw const ApiFailure(FailureKind.server, '分析结果未提供，请刷新');
    }
    return AiJob._(data, input, output, sources);
  }
  String get id => data['id'] as String;
  int get version => (data['version'] as num).toInt();
  String get state => data['state'] as String;
  String get error => '${data['error'] ?? '生成失败，请重试'}';
  String get summary => '${output?['summary'] ?? ''}';
  bool get running => state == 'QUEUED' || state == 'RUNNING';
  List<Map<String, dynamic>> get actions =>
      output == null ? [] : aiObjects(output!['actions'], max: 3);
  List<Map<String, dynamic>> get nodes =>
      output == null ? [] : aiObjects(output!['nodes'], max: 10);
  List<AiSource> refs(dynamic ids) {
    final wanted = aiIds(ids);
    return sources.where((s) => wanted.contains(s.id)).toList();
  }

  bool validRefs(dynamic ids, String account) {
    final wanted = aiIds(ids);
    return wanted.isNotEmpty &&
        wanted.toSet().length == wanted.length &&
        wanted.every(
          (id) => sources.any((s) => s.id == id && s.route(account) != null),
        );
  }

  Map<String, dynamic> draft(String summary, List<String> titles) => {
    'version': version,
    'summary': summary,
    'sourceIds': aiIds(output?['sourceIds']),
    'nodes': nodes,
    'actions': [
      for (var i = 0; i < actions.length; i++)
        {...actions[i], 'title': titles[i]},
    ],
  };
}

class AiStreamEvent {
  const AiStreamEvent(this.kind, this.data);
  final String kind;
  final Map<String, dynamic> data;
}
