import 'package:pandora_mobile/shared/sibling_swipe.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/ai.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/ai_repository.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';

final latestAiJobProvider = StateProvider.family<String?, String>(
  (ref, account) => null,
);
String aiScope(Session user) => switch (user.role) {
  UserRole.admin || UserRole.founder => '本人及授权公司范围',
  UserRole.director => '本人及授权部门范围',
  UserRole.leader => '本人及授权团队范围',
  _ => '本人及明确授权的任务',
};
String aiDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String aiPeriod(dynamic value) => switch (value) {
  'week' => '周报',
  'month' => '月报',
  _ => '日报',
};
String aiTime(dynamic time) {
  final date = DateTime.tryParse('$time')?.toLocal();
  return date == null
      ? '未提供时间'
      : '${aiDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String aiError(Object e) => e is ApiFailure
    ? switch (e.code) {
        'AI_NOT_CONFIGURED' => '企业AI服务尚未配置，日志和任务功能仍可使用',
        'AI_BUDGET' => '今日AI预算不足，请稍后再试',
        'RATE_LIMIT' || 'RATE_LIMITED' => '请求过于频繁，请稍后再试',
        'AI_INPUT_TOO_LARGE' => '来源内容过多，请缩小日期周期',
        _ => e.toString(),
      }
    : '分析暂时无法读取，请重试';
bool aiDenied(Object e) =>
    e is ApiFailure &&
    [FailureKind.forbidden, FailureKind.unauthorized].contains(e.kind);

/// Cancels page-local transport and rejects late results from replaced sessions.
abstract class AiProtectedState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  late final Session originalAccount = ref.read(sessionProvider);
  CancelToken? transport;
  bool denied = false;
  String? error;
  bool get alive =>
      mounted &&
      !denied &&
      ref.read(sessionProvider).id == originalAccount.id &&
      ref.read(sessionProvider).token == originalAccount.token &&
      ref.read(sessionProvider).canReadBusiness;
  CancelToken nextTransport() {
    transport?.cancel();
    return transport = CancelToken();
  }

  bool guard() {
    ref.watch(sessionProvider);
    ref.listen(sessionProvider, (_, next) {
      if (next.id != originalAccount.id ||
          next.token != originalAccount.token ||
          !next.canReadBusiness) {
        transport?.cancel();
        if (mounted) {
          setState(() {
            denied = true;
            clearProtected();
          });
        }
      }
    });
    return alive;
  }

  void clearProtected() {}
  void fail(Object e) {
    if (!mounted) return;
    setState(() {
      error = aiError(e);
      if (aiDenied(e)) {
        denied = true;
        clearProtected();
        transport?.cancel();
      }
    });
  }

  Widget deniedPage() => const PageFrame(
    title: 'AI地图',
    child: Center(child: Text('访问已停止，请返回后重新确认账号与权限')),
  );
  @override
  void dispose() {
    transport?.cancel();
    super.dispose();
  }
}

class AiSources extends ConsumerWidget {
  const AiSources(this.job, this.ids, {super.key, this.onPurpose});
  final AiJob job;
  final dynamic ids;
  final void Function(String purpose, String source)? onPurpose;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = job.data['owner_id']?.toString() ?? '';
    final session = ref.watch(sessionProvider);
    if (session.id != account || !session.canReadBusiness) {
      return const Text('来源访问已停止，请重新确认账号与权限');
    }
    final wanted = aiIds(ids);
    final sources = job.refs(ids);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wanted.isEmpty || sources.length != wanted.length)
          const Text('部分依据缺失，建议尚未证实，请重新读取来源。'),
        for (final source in sources)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              source.id.startsWith('log:')
                  ? Icons.description_outlined
                  : source.id.startsWith('task:')
                  ? Icons.assignment_outlined
                  : Icons.flag_outlined,
            ),
            title: Text(source.title),
            subtitle: Text(
              '${source.overdue ? '规则识别：已逾期 · ' : ''}${source.route(account) == null ? '来源链接不可用' : '查看原始记录'}',
            ),
            onTap: source.route(account) == null
                ? null
                : () => context.push(source.route(account)!),
            trailing: onPurpose == null || source.route(account) == null
                ? const Icon(Icons.chevron_right)
                : PopupMenuButton<String>(
                    tooltip: '分析此来源',
                    onSelected: (p) => onPurpose!(p, source.id),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'EXPLAIN_RISK', child: Text('解释风险')),
                      PopupMenuItem(value: 'SPLIT_STEPS', child: Text('拆分步骤')),
                      PopupMenuItem(value: 'DRAFT_TASK', child: Text('起草任务建议')),
                    ],
                  ),
          ),
      ],
    );
  }
}

class ServerAiPage extends ConsumerStatefulWidget {
  const ServerAiPage({super.key});
  @override
  ConsumerState<ServerAiPage> createState() => _ServerAiPageState();
}

class _ServerAiPageState extends AiProtectedState<ServerAiPage> {
  DateTime date = DateTime.now();
  String period = 'day';
  AiJob? current, completed;
  bool busy = false, connected = false;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final id = ref.read(latestAiJobProvider(originalAccount.id));
      if (id != null && alive) refresh(id);
    });
  }

  @override
  void clearProtected() {
    current = null;
    completed = null;
  }

  void accept(AiJob job) {
    if (!alive || job.data['owner_id'] != originalAccount.id) {
      if (alive) fail(const ApiFailure(FailureKind.forbidden, '该分析不属于当前账号'));
      return;
    }
    setState(() {
      current = job;
      if (job.state == 'SUCCEEDED') completed = job;
    });
    ref.read(latestAiJobProvider(originalAccount.id).notifier).state = job.id;
  }

  Future<void> refresh(String id) async {
    if (!alive || busy) return;
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await repo.job(id, token: token);
      if (alive && !token.isCancelled) accept(result);
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive && !token.isCancelled) setState(() => busy = false);
    }
  }

  Future<void> generate({
    String purpose = 'SUMMARY',
    String? source,
    bool retry = false,
  }) async {
    if (!alive || busy || current?.running == true) return;
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final job = retry && current != null
          ? await repo.retry(current!.id, token: token)
          : await repo.create(
              source == null ? aiDate(date) : '${completed!.input['date']}',
              source == null ? period : '${completed!.input['period']}',
              purpose: purpose,
              focus: source,
              token: token,
            );
      if (!alive || token.isCancelled) return;
      accept(job);
      if (job.running) await consume(repo, job, token);
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive && !token.isCancelled) {
        setState(() {
          busy = false;
          connected = false;
        });
      }
    }
  }

  Future<void> consume(AiRepository repo, AiJob job, CancelToken token) async {
    setState(() => connected = true);
    try {
      await for (final event in repo.stream(job.id, token)) {
        if (!alive || token.isCancelled) return;
        // SSE partial JSON is deliberately not published as a sourced recommendation.
        if (event.kind == 'result') break;
      }
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    }
    if (!alive || token.isCancelled) return;
    final finalJob = await repo.job(job.id, token: token);
    if (alive && !token.isCancelled) accept(finalJob);
  }

  Future<void> cancelJob() async {
    if (!alive || current?.running != true) return;
    final repo = ref.read(aiRepositoryProvider),
        id = current!.id,
        token = nextTransport();
    setState(() {
      busy = true;
      connected = false;
      error = null;
    });
    try {
      await repo.cancel(id, token: token);
      final job = await repo.job(id, token: token);
      if (alive && !token.isCancelled) accept(job);
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive && !token.isCancelled) setState(() => busy = false);
    }
  }

  Future<void> openJob(String path) async {
    await context.push(path);
    if (alive && !busy && current != null) await refresh(current!.id);
  }

  Future<void> reconnect() async {
    if (!alive || busy || current?.running != true) return;
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await consume(repo, current!, token);
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive && !token.isCancelled) {
        setState(() {
          busy = false;
          connected = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!guard()) return deniedPage();
    ref.listen(latestAiJobProvider(originalAccount.id), (_, id) {
      if (id != null && id != current?.id && alive && !busy) refresh(id);
    });
    final job = completed;
    final page = PageFrame(
      title: 'AI地图',
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SunnyPrimaryButton.icon(
          loading: busy,
          onPressed: busy || current?.running == true ? null : () => generate(),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('开始分析'),
        ),
      ),
      child: PageBody(
        children: [
          PillTabs(
            labels: const ['发展分析', '堵点风险', '行动规划'],
            wrapLabels: true,
            selected: tab,
            onChanged: (v) => setState(() => tab = v),
          ),
          const SizedBox(height: 12),
          if (error != null)
            ErrorPanel(
              error!,
              retry: current == null
                  ? () => generate()
                  : () => refresh(current!.id),
            ),
          if (current != null && current!.state != 'SUCCEEDED')
            PaperSurface(
              color: const Color(0xFFFFF0DA),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TuantuanArt(
                      TuantuanAssets.aiAssets[current!.state == 'FAILED'
                          ? 'warning'
                          : 'thinking']!,
                      width: 68,
                      height: 60,
                    ),
                  ),
                  Text(switch (current!.state) {
                    'QUEUED' => '已排队，等待生成',
                    'RUNNING' => connected ? '正在接收分析，结果尚未确认' : '服务端仍在生成，可刷新状态',
                    'SUCCEEDED' => '建议草稿已生成',
                    'FAILED' => '生成未完成：${current!.error}',
                    _ => '生成已取消，输入保留',
                  }),
                  Text(
                    '${current!.input['date']} · ${switch (current!.input['period']) {
                      'week' => '周',
                      'month' => '月',
                      _ => '日',
                    }}范围',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (current!.running)
                        TextButton(
                          onPressed: connected
                              ? null
                              : () => refresh(current!.id),
                          child: const Text('刷新状态'),
                        ),
                      if (current!.running && !connected)
                        TextButton(
                          onPressed: busy ? null : reconnect,
                          child: const Text('继续接收'),
                        ),
                      if (current!.running)
                        TextButton(
                          onPressed: cancelJob,
                          child: const Text('取消生成'),
                        ),
                      if (['FAILED', 'CANCELLED'].contains(current!.state))
                        TextButton(
                          onPressed: busy ? null : () => generate(retry: true),
                          child: const Text('重试生成'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (job != null) ...[
            const SizedBox(height: 20),
            if (job.id != current?.id) const Text('以下为上一次完成的结果，当前生成尚未替换它。'),
            if (tab == 0) ...[
              Text(job.summary, style: const TextStyle(height: 1.7)),
              const SizedBox(height: 12),
              AiSources(
                job,
                job.output?['sourceIds'],
                onPurpose: busy || current?.running == true
                    ? null
                    : (p, s) => generate(purpose: p, source: s),
              ),
            ],
            if (tab == 1) ...[
              Text(
                '规则识别：本次来源中 ${job.sources.where((s) => s.overdue).length} 个任务已逾期。此标记来自服务端，不是AI猜测。',
              ),
              const Divider(height: 24),
              const Text(
                'AI风险推测 · 需核实实际影响',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final node in job.nodes.where(
                (n) => ['RISK', 'BLOCKER'].contains(n['type']),
              )) ...[
                Text('${node['title']}'),
                AiSources(
                  job,
                  node['sourceIds'],
                  onPurpose: busy || current?.running == true
                      ? null
                      : (p, s) => generate(purpose: p, source: s),
                ),
              ],
              if (!job.nodes.any(
                (n) => ['RISK', 'BLOCKER'].contains(n['type']),
              ))
                const Text('本次未提供风险节点，不代表没有业务风险。'),
            ],
            if (tab == 2) ...[
              const Text('建议保持草稿，人工核对来源、负责人和期限后再确认任务。'),
              for (final (index, action) in job.actions.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${action['title']}'),
                  subtitle: Text(
                    '来源 ${aiIds(action['sourceIds']).length} 条 · 建议待核实',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      openJob('/ai/jobs/${encode(job.id)}/actions/$index'),
                ),
              if (job.actions.isEmpty) const Text('本次没有可执行建议。'),
            ],
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
    return SiblingSwipe(
      index: job == null ? 0 : tab,
      itemCount: job == null ? 1 : 3,
      onStep: (step) {
        if (job == null) return false;
        final next = tab + step;
        if (next < 0 || next > 2) return false;
        setState(() => tab = next);
        return true;
      },
      child: page,
    );
  }
}
