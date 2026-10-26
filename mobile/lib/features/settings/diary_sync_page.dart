import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/errors/api_failure.dart';
import '../../core/state/local_state.dart';
import '../../core/state/providers.dart';
import '../../data/local/draft_store.dart';
import '../../data/models/models.dart';
import '../../data/models/diary_task_links.dart';
import '../../data/repositories/complete_list.dart';
import '../../shared/paper_layout.dart';
import '../../shared/widgets.dart';
import '../../shared/premium_pickers.dart';
import '../dashboard/diary_composer_sheet.dart';

String diaryDayKey(DateTime day) => DraftLocation.diary('', day).object;

DateTime? validDiaryDay(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final day = DateTime.tryParse(value);
  return day != null &&
          day.year >= 2020 &&
          day.year <= 2100 &&
          diaryDayKey(day) == value
      ? day
      : null;
}

class DiarySyncSnapshot {
  const DiarySyncSnapshot(this.local, this.server, this.serverError);
  final LocalDraft? local;
  final Record? server;
  final Object? serverError;
}

/// A read-only comparison; writes and conflict replacement stay in the editor.
final diarySyncProvider = FutureProvider.autoDispose
    .family<DiarySyncSnapshot, (String, String?, int?)>((ref, key) async {
      final session = ref.watch(sessionProvider);
      final day = validDiaryDay(key.$1);
      if (day == null ||
          (key.$2 == null) != (key.$3 == null) ||
          key.$2?.trim().isEmpty == true ||
          key.$3 != null && key.$3! < 1) {
        throw const ApiFailure(FailureKind.validation, '日志日期或原版本无效，请从日志重新进入');
      }
      if (!session.canReadBusiness) {
        throw const ApiFailure(FailureKind.forbidden, '请确认账号业务访问权限');
      }
      var active = true;
      ref.onDispose(() => active = false);
      final repository = ref.watch(repositoryProvider);
      final local = await ref
          .watch(draftStoreProvider)
          .read(
            key.$2 == null
                ? DraftLocation.diary(session.id, day)
                : DraftLocation.revision(session.id, key.$2!, key.$3!),
          );
      void checkActive() {
        if (!active) throw const ApiFailure(FailureKind.unavailable, '读取已停止');
      }

      checkActive();
      try {
        var id = key.$2;
        if (id == null) {
          final range = BusinessRange(day, '日');
          final page = await readCompleteList(
            repository,
            'logs',
            Query(ownerId: session.id, from: range.from, to: range.to),
            isActive: () => active,
          );
          if (page.items.any(
            (r) =>
                r.ownerId != session.id || r.fields['businessDate'] != key.$1,
          )) {
            throw const ApiFailure(FailureKind.forbidden, '返回的日志不属于当前账号或业务日期');
          }
          if (page.items.length > 1) {
            throw const ApiFailure(FailureKind.conflict, '该日期返回了多份日志，请从日志详情核对');
          }
          id = page.items.firstOrNull?.id ?? local?.serverId;
        }
        checkActive();
        if (id == null) return DiarySyncSnapshot(local, null, null);
        final server = await repository.detail('logs', id);
        checkActive();
        if (server.ownerId != session.id ||
            server.fields['businessDate'] != key.$1) {
          throw const ApiFailure(FailureKind.forbidden, '返回的日志不属于当前账号或业务日期');
        }
        return DiarySyncSnapshot(local, server, null);
      } catch (error) {
        checkActive();
        if (error is ApiFailure &&
            [
              FailureKind.forbidden,
              FailureKind.unauthorized,
            ].contains(error.kind)) {
          rethrow;
        }
        return DiarySyncSnapshot(local, null, error);
      }
    });

class DiarySyncPage extends ConsumerStatefulWidget {
  const DiarySyncPage({super.key, this.date, this.id, this.version});
  final String? date, id, version;
  @override
  ConsumerState<DiarySyncPage> createState() => _DiarySyncPageState();
}

class _DiarySyncPageState extends ConsumerState<DiarySyncPage> {
  late String date;
  @override
  void initState() {
    super.initState();
    date = widget.date ?? diaryDayKey(ref.read(logDateProvider));
  }

  (String, String?, int?) get query => (
    date,
    widget.id,
    widget.version == null ? null : int.tryParse(widget.version!) ?? -1,
  );

  void edit(DiarySyncSnapshot snapshot) {
    final day = validDiaryDay(date)!;
    ref.read(logDateProvider.notifier).state = day;
    final server = snapshot.server;
    final submitted = server != null && isSubmittedDiary(server);
    // An original local version must reach the editor, including when stale.
    final version = widget.id != null
        ? query.$3
        : snapshot.local?.serverVersion ?? server?.version;
    final carryDiary = submitted && widget.id == null && snapshot.local != null;
    if (server != null && submitted) {
      context.push(
        '/form/log-revise'
        '?id=${encode(server.id)}&version=${version ?? server.version}'
        '${carryDiary ? "&draftSource=diary" : ""}',
      );
    } else {
      unawaited(
        showDiaryComposer(
          context,
          ref,
          date: day,
          recordId: server?.id ?? snapshot.local?.serverId,
          version: version ?? snapshot.local?.serverVersion ?? server?.version,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = diarySyncProvider(query),
        state = ref.watch(diarySyncProvider(query));
    final snapshot = state.isLoading || state.hasError
        ? null
        : state.valueOrNull;
    final canEdit = snapshot != null && snapshot.serverError == null;
    return PageFrame(
      title: '草稿与同步',
      bottom: BottomActions(
        primary: SunnyPrimaryButton.icon(
          onPressed: canEdit ? () => edit(snapshot) : null,
          icon: const Icon(Icons.edit_note),
          label: const Text('继续编辑'),
        ),
        secondary: OutlinedButton(
          onPressed: state.isLoading ? null : () => ref.invalidate(provider),
          child: const Text('重新检查'),
        ),
        note: '检查只读取版本；不会覆盖本机内容，也不会提交日志。',
      ),
      child: PageBody(
        children: [
          if (widget.id == null)
            TextButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text(date),
              onPressed: () async {
                final selected = await showPremiumDatePicker(
                  context,
                  initial: validDiaryDay(date) ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (mounted && selected != null) {
                  setState(() => date = diaryDayKey(selected));
                }
              },
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('业务日期 $date · 原版本 v${widget.version ?? "未指定"}'),
            ),
          state.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const LoadingSkeleton(),
            error: (e, _) =>
                RecordFailure(e, retry: () => ref.invalidate(provider)),
            data: (data) {
              final local = data.local, server = data.server;
              final originalVersion = widget.id != null
                  ? query.$3
                  : local?.serverVersion;
              final stale =
                  server != null &&
                  originalVersion != null &&
                  originalVersion != server.version;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PaperSurface(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          local == null ? '此日期没有本机草稿' : '本机草稿已保留',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (local != null)
                          Text('保存于 ${_savedLabel(local.savedAt)}'),
                        if (originalVersion != null)
                          Text('编辑依据 v$originalVersion'),
                        const Text('本机保存不等于服务器提交。'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (data.serverError != null)
                    RecordFailure(
                      data.serverError!,
                      retry: () => ref.invalidate(provider),
                    )
                  else if (server == null)
                    const Text('服务器暂无该日期日志，可以继续本机编辑。')
                  else ...[
                    Text(
                      '${isSubmittedDiary(server) ? "当前生效" : "服务器草稿"} · v${server.version}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      stale
                          ? '服务器版本已变化。本机原稿保持不变，编辑器将要求明确重新读取。'
                          : '下方分别展示本机内容与服务器版本，请核对后再编辑。',
                    ),
                  ],
                  if (local != null || server != null) ...[
                    const SizedBox(height: 24),
                    PaperSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final field in [
                            '今日工作',
                            '关联任务',
                            '遇到的阻碍',
                            '明日计划',
                            '工时',
                          ]) ...[
                            Text(
                              field,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '本机',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(
                              local?.fields[field]?.isNotEmpty == true
                                  ? field == '关联任务'
                                        ? _taskSummary(local!.fields[field])
                                        : local!.fields[field]!
                                  : '暂无内容',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '服务器',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(
                              data.serverError != null
                                  ? '未读取成功'
                                  : field == '关联任务'
                                  ? _taskSummary(
                                      server?.fields['taskIds'] ??
                                          server?.fields[field],
                                    )
                                  : '${server?.fields[field] ?? "暂无内容"}',
                            ),
                            const Divider(height: 32),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/logs'),
                    child: const Text('返回日志'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _savedLabel(DateTime instant) {
    final wall = shanghaiWallTime(instant);
    return '${diaryDayKey(wall)} ${wall.hour.toString().padLeft(2, "0")}:${wall.minute.toString().padLeft(2, "0")}';
  }

  String _taskSummary(dynamic value) {
    try {
      return DiaryTaskLinks.describe(value);
    } catch (_) {
      return '关联任务格式无效，请返回原日志重新读取';
    }
  }
}
