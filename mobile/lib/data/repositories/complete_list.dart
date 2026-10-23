import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'repository.dart';

/// Reads an existing scoped cursor contract without reporting partial data as complete.
Future<PageResult> readCompleteList(
  Repository repository,
  String resource,
  Query query, {
  bool Function()? isActive,
}) async {
  final all = <Record>[], ids = <String>{}, cursors = <String>{};
  String? cursor = query.cursor;
  int? expectedTotal;
  while (true) {
    if (isActive?.call() == false) {
      throw const ApiFailure(FailureKind.unavailable, '读取已停止，请重新进入');
    }
    if (!cursors.add(cursor ?? '0')) {
      throw const ApiFailure(FailureKind.server, '分页返回了重复位置，请重新加载');
    }
    final page = await repository.list(
      resource,
      Query(
        search: query.search,
        ownerId: query.ownerId,
        departmentId: query.departmentId,
        from: query.from,
        to: query.to,
        cursor: cursor,
      ),
    );
    if (isActive?.call() == false) {
      throw const ApiFailure(FailureKind.unavailable, '读取已停止，请重新进入');
    }
    expectedTotal ??= page.total;
    if (expectedTotal != page.total) {
      throw const ApiFailure(FailureKind.conflict, '记录列表已变化，请重新加载完整内容');
    }
    for (final item in page.items) {
      if (!ids.add(item.id)) {
        throw const ApiFailure(FailureKind.conflict, '分页记录重复，请重新加载完整内容');
      }
      all.add(item);
    }
    if (all.length > expectedTotal || expectedTotal < 0) {
      throw const ApiFailure(FailureKind.server, '分页记录数量不一致，请重新加载');
    }
    if (all.length == expectedTotal) {
      return PageResult(List.unmodifiable(all), total: expectedTotal);
    }
    if (page.items.isEmpty ||
        page.nextCursor == null ||
        page.nextCursor!.isEmpty) {
      throw const ApiFailure(FailureKind.server, '记录尚未读取完整，请重新加载');
    }
    cursor = page.nextCursor;
  }
}
