import 'dart:convert';
import '../../core/errors/api_failure.dart';

/// Lossless task IDs in the existing encrypted string draft field.
/// Old single-ID drafts require no key or database migration.
class DiaryTaskLinks {
  static List<String> parse(dynamic value) {
    if (value == null || value == '') return [];
    dynamic decoded = value;
    if (value is String) {
      if (value.trim().startsWith('[')) {
        try {
          decoded = jsonDecode(value);
        } on FormatException {
          throw const ApiFailure(FailureKind.validation, '关联任务数据无效，请重新读取原日志');
        }
      } else {
        decoded = [value];
      }
    }
    if (decoded is! List ||
        decoded.any(
          (id) =>
              id is! String ||
              id.trim().isEmpty ||
              RegExp(r'[\x00-\x1f]').hasMatch(id),
        )) {
      throw const ApiFailure(FailureKind.validation, '关联任务数据无效，请重新读取原日志');
    }
    return decoded.cast<String>().toSet().toList();
  }

  static String encode(dynamic value) {
    final ids = parse(value);
    if (ids.isEmpty) return '';
    if (ids.length == 1 && !ids.single.trim().startsWith('[')) {
      return ids.single;
    }
    return jsonEncode(ids);
  }

  static String describe(dynamic value) {
    final ids = parse(value);
    return ids.isEmpty ? '未关联任务' : ids.join('、');
  }
}
