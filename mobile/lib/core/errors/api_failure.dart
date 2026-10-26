import 'package:dio/dio.dart';

enum FailureKind {
  timeout,
  unauthorized,
  forbidden,
  validation,
  notFound,
  conflict,
  server,
  unavailable,
}

class ApiFailure implements Exception {
  const ApiFailure(this.kind, this.message, {this.traceId, this.code});
  final FailureKind kind;
  final String message;
  final String? traceId;
  final String? code;
  factory ApiFailure.fromDio(DioException e) {
    final data = e.response?.data;
    final code = data is Map ? data['code']?.toString() : null;
    final kind = switch (e.response?.statusCode) {
      401 => FailureKind.unauthorized,
      403 => FailureKind.forbidden,
      404 => FailureKind.notFound,
      409 => FailureKind.conflict,
      503 => FailureKind.unavailable,
      400 || 413 || 415 || 422 => FailureKind.validation,
      _ =>
        [
              DioExceptionType.connectionTimeout,
              DioExceptionType.receiveTimeout,
              DioExceptionType.sendTimeout,
            ].contains(e.type)
            ? FailureKind.timeout
            : e.type == DioExceptionType.connectionError
            ? FailureKind.unavailable
            : FailureKind.server,
    };
    final message = switch (code) {
      'UNSUPPORTED_FILE' => '请添加PNG、JPEG、PDF、Word或Excel文件',
      'FILE_TYPE_MISMATCH' => '文件格式与名称不一致，请重新导出后添加',
      'FILE_LIMIT' || 'FILE_TOO_LARGE' => '材料超出处理范围，请缩小或拆分后重试',
      'FILE_UNSAFE' => '材料含有宏、外部链接或嵌入对象，请移除后重新导出',
      'FILE_ENCRYPTED' => '请先解除文件加密，再添加材料',
      'FILE_UNREADABLE' => '材料暂时无法读取，请换一份完整文件',
      'FILE_TIMEOUT' => '这份材料处理时间过长，请拆分后重试',
      'AI_NOT_CONFIGURED' => 'DeepSeek 尚未配置，已有记忆仍可查看',
      'AI_BUDGET' => '今日 AI 预算已用尽，请稍后再试',
      'AI_PROVIDER_FAILED' => '模型服务暂时不可用，请稍后重试',
      'MEMORY_SOURCE_STALE' => '来源已有新版本，请刷新分析与证据',
      'OUTCOME_PENDING' => '正在核对办理结果，请稍候再补充，也可以停止后续办理',
      'INVALID_CREDENTIALS' =>
        e.requestOptions.path.endsWith('/password')
            ? '原密码错误，请重新填写'
            : '账号或密码错误，请重新填写',
      'PASSWORD_CHANGE_REQUIRED' => '首次登录请先修改密码',
      'MEMBERSHIP_PENDING' => '部门归属尚未确认，请刷新申请状态',
      'ACCOUNT_DISABLED' => '账号已停用，请联系管理员',
      'PASSWORD_UNCHANGED' => '新密码需与原密码不同',
      'PASSWORD_POLICY' => '密码至少12个字符，UTF-8编码不超过72字节',
      'LOG_EDIT_WINDOW_EXPIRED' => '日报首次提交已满24小时，不能再修改或撤回',
      'RATE_LIMITED' => '请求过于频繁，请稍后再试',
      _ => switch (kind) {
        FailureKind.unauthorized => '登录已失效，请重新登录',
        FailureKind.forbidden => '你没有访问这项内容的权限',
        FailureKind.notFound => '内容不存在或已被移除',
        FailureKind.conflict => '内容已有新版本，请刷新后再提交',
        FailureKind.validation => '请检查填写的内容',
        FailureKind.timeout => '连接超时，请稍后重试',
        FailureKind.unavailable => '无法连接企业服务，请确认后端已启动及连接地址正确',
        _ => '服务暂时不可用，请稍后重试',
      },
    };
    return ApiFailure(
      kind,
      message,
      traceId: e.response?.headers.value('x-trace-id'),
      code: code,
    );
  }
  @override
  String toString() => message;
}

/// Retains confirmed draft identity if the following submit request fails.
/// Contains no diary body; UI can retry the same draft using its saved version.
class DiarySubmitFailure extends ApiFailure {
  DiarySubmitFailure(ApiFailure failure, this.draftId, this.draftVersion)
    : super(
        failure.kind,
        failure.message,
        traceId: failure.traceId,
        code: failure.code,
      );
  final String draftId;
  final int draftVersion;
}
