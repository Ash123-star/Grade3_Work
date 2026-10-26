import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/memory_client.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/shared/widgets.dart';

class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});
  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  Map<String, dynamic> scope = {'domain': 'PERSONAL'};
  Map<String, dynamic> preferences = {}, knowledge = {}, analysis = {};
  List<Map<String, dynamic>> scopes = [];
  String? error;
  String? account;
  bool loading = true, working = false;
  int generation = 0;
  Timer? timer;
  MemoryClient get client => ref.read(memoryClientProvider);
  Map<String, dynamic> get output =>
      Map<String, dynamic>.from(analysis['output'] as Map? ?? {});
  bool get personal => scope['domain'] == 'PERSONAL';
  List<Map<String, dynamic>> entries(String key) => (output[key] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final ticket = ++generation;
    timer?.cancel();
    setState(() {
      loading = true;
      error = null;
      working = false;
      analysis = {};
    });
    if (AppConfig.mock) {
      setState(() {
        loading = false;
        analysis = {};
        knowledge = {};
        preferences = {};
        scopes = [];
      });
      return;
    }
    try {
      final result = await client.call(
        'GET',
        '/ai-maps/development',
        query: scope,
      );
      final status = await client.call(
        'GET',
        '/ai-memories/knowledge-status',
        query: scope,
      );
      final prefs = personal
          ? await client.call('GET', '/ai-memories/preferences/me')
          : <String, dynamic>{};
      if (!mounted || ticket != generation) return;
      setState(() {
        analysis = Map<String, dynamic>.from(result['analysis'] as Map? ?? {});
        scopes = (result['scopes'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        knowledge = status;
        preferences = prefs;
        loading = false;
        working = ['QUEUED', 'RUNNING'].contains(analysis['state']);
      });
      if (working) poll(analysis['id'].toString(), ticket);
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() {
          loading = false;
          error = e.toString();
        });
      }
    }
  }

  void poll(String id, int ticket) {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 2), () async {
      try {
        final job = await client.call('GET', '/ai-maps/development/jobs/$id');
        if (!mounted || ticket != generation) return;
        setState(() {
          analysis = job;
          working = ['QUEUED', 'RUNNING'].contains(job['state']);
        });
        if (working) poll(id, ticket);
      } catch (e) {
        if (mounted && ticket == generation) {
          setState(() {
            error = e.toString();
            working = false;
          });
        }
      }
    });
  }

  Future<void> generate() async {
    final ticket = generation;
    setState(() {
      working = true;
      error = null;
    });
    try {
      final job = await client.call(
        'POST',
        '/ai-maps/development/jobs',
        body: scope,
        headers: {
          'Idempotency-Key':
              'development-${DateTime.now().microsecondsSinceEpoch}',
        },
      );
      if (!mounted || ticket != generation) return;
      setState(() => analysis = job);
      poll(job['id'].toString(), ticket);
    } catch (e) {
      if (mounted && ticket == generation) {
        setState(() {
          working = false;
          error = e.toString();
        });
      }
    }
  }

  Future<void> editGoal() async {
    final goals = TextEditingController(
      text: preferences['explicit_goals'] as String? ?? '',
    );
    final prefs = TextEditingController(
      text: preferences['response_preferences'] as String? ?? '',
    );
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('我的目标与偏好'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: goals,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '希望发展的方向'),
                ),
                TextField(
                  controller: prefs,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '建议偏好与可投入时间'),
                ),
                const Text('仅本人可见。更新后，下一次分析会使用新目标。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              'version': preferences['version'] ?? 0,
              'explicitGoals': goals.text.trim(),
              'responsePreferences': prefs.text.trim(),
            }),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    try {
      await client.call('PUT', '/ai-memories/preferences/me', body: value);
      await load();
    } catch (e) {
      if (mounted) notice(context, e.toString());
    }
  }

  Future<void> memoryPanel() async {
    try {
      final data = await client.call('GET', '/ai-memories', query: scope);
      if (!mounted) return;
      final items = (data['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .75,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('记忆知识库', style: Theme.of(ctx).textTheme.titleLarge),
                  Text(
                    '已入库 ${knowledge['memories'] ?? 0} 条 · 已索引 ${knowledge['indexedMemories'] ?? 0} 条',
                  ),
                  const Text('显示前 30 条；正式业务事实纠正应进入原记录修订。'),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      editMemory(null);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('补充经历'),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('还没有有效记忆，提交工作日志或补充经历后再来。'),
                          ),
                        for (final item in items)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['content'].toString()),
                                  Text(
                                    '${item['claim_type']} · ${item['status']} · 来源版本 ${item['source_version']}',
                                    style: const TextStyle(
                                      color: CuteTokens.muted,
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          editMemory(item);
                                        },
                                        child: const Text('纠正'),
                                      ),
                                      if (item['status'] == 'CANDIDATE')
                                        TextButton(
                                          onPressed: () async {
                                            Navigator.pop(ctx);
                                            try {
                                              await client.call(
                                                'POST',
                                                '/ai-memories/${item['id']}/confirm',
                                                body: {
                                                  'version': item['version'],
                                                  'reason': '确认候选记忆',
                                                },
                                              );
                                              await load();
                                            } catch (e) {
                                              if (mounted) {
                                                notice(context, e.toString());
                                              }
                                            }
                                          },
                                          child: const Text('确认观察'),
                                        ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          forget(item);
                                        },
                                        child: const Text('停止记忆'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) notice(context, e.toString());
    }
  }

  Future<void> editMemory(Map<String, dynamic>? item) async {
    final content = TextEditingController(
      text: item?['content'] as String? ?? '',
    );
    final reason = TextEditingController();
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item == null ? '补充经历' : '纠正记忆'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: content,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: '经历与成果'),
                ),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: '说明理由（组织变更需审核）'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (content.text.trim().isEmpty) return;
              Navigator.pop(
                ctx,
                item == null
                    ? {
                        ...scope,
                        'category': 'EXPERIENCE',
                        'claimType': 'FACT',
                        'content': content.text.trim(),
                        'reason': reason.text.trim(),
                      }
                    : {
                        'version': item['version'],
                        'reason': reason.text.trim(),
                        'candidate': {'content': content.text.trim()},
                      },
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    try {
      final result = await client.call(
        'POST',
        item == null ? '/ai-memories' : '/ai-memories/${item['id']}/revisions',
        body: value,
      );
      if (mounted) {
        notice(
          context,
          result['status'] == 'PENDING'
              ? '已提交直属上级审核，尚未生效'
              : result['message'] as String? ?? '记忆已更新',
        );
      }
      await load();
    } catch (e) {
      if (mounted) notice(context, e.toString());
    }
  }

  Future<void> forget(Map<String, dynamic> item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('停止使用这条来源的记忆？'),
        content: const Text('停止用于当前记忆范围的分析，不删除原始工作记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('停止记忆'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await client.call(
        'DELETE',
        '/ai-memories/${item['id']}',
        headers: {'If-Match': item['version'].toString()},
      );
      if (mounted) notice(context, '已停止使用，后台正在清理索引与图谱');
      await load();
    } catch (e) {
      if (mounted) notice(context, e.toString());
    }
  }

  Future<void> evidence() async {
    try {
      final data = await client.call(
        'GET',
        '/ai-maps/development/${analysis['id']}/evidence',
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .65,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('RAG 分析依据', style: Theme.of(ctx).textTheme.titleLarge),
                for (final item in data['items'] as List? ?? [])
                  ListTile(
                    title: Text(item['text'].toString()),
                    subtitle: Text(
                      '${item['id']}\n${item['locator']} · ${item['provenance']}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) notice(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final scenario = ref.watch(scenarioProvider);
    if (account != user.id) {
      account = user.id;
      scope = {'domain': 'PERSONAL'};
      generation++;
      analysis = {};
      preferences = {};
      knowledge = {};
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
    return PageFrame(
      title: 'AI 地图',
      actions: [
        IconButton(
          tooltip: '管理记忆',
          onPressed: AppConfig.mock ? null : memoryPanel,
          icon: const Icon(Icons.history),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '成长与发展地图',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('记住做过的事，用成果和目标看清下一步。'),
          const SizedBox(height: 16),
          if (AppConfig.mock) ...[
            const DemoLabel(),
            EmptyIllustration(
              title: scenario == DemoScenario.forbidden
                  ? '暂无分析访问权限'
                  : scenario == DemoScenario.offline
                  ? '分析暂时无法加载'
                  : '从真实工作记录开始',
              subtitle: '完成工作记录后，可在这里查看已积累的个人与公司记忆。',
            ),
          ] else if (!user.active)
            const EmptyIllustration(
              title: '请先登录',
              subtitle: '登录后仅使用当前账号有权查看的记忆。',
            )
          else ...[
            if (scopes.length > 1)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in scopes)
                    ChoiceChip(
                      label: Text(option['label'].toString()),
                      selected:
                          scope['domain'] == option['domain'] &&
                          (scope['scopeId'] == null ||
                              scope['scopeId'] == option['scopeId']),
                      onSelected: (_) {
                        scope = {
                          'domain': option['domain'],
                          'scopeType': option['scopeType'],
                          'scopeId': option['scopeId'],
                        };
                        load();
                      },
                    ),
                ],
              ),
            if (personal)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  preferences['explicit_goals']?.toString().isNotEmpty == true
                      ? '目标：${preferences['explicit_goals']}'
                      : '尚未设置个人目标',
                ),
                subtitle: const Text('本人目标与偏好仅自己可见'),
                trailing: TextButton(
                  onPressed: editGoal,
                  child: const Text('编辑目标'),
                ),
              ),
            Text(
              '有效记忆 ${knowledge['memories'] ?? 0} 条 · 已索引 ${knowledge['indexedMemories'] ?? 0} 条 · 更新中 ${knowledge['indexingMemories'] ?? 0} 条 · 待确认 ${knowledge['candidates'] ?? 0} 条',
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: SunnyLoadingIndicator(size: 26)),
              ),
            if (error != null) ErrorPanel(error!, retry: load),
            if (working)
              const ListTile(
                leading: SunnyLoadingIndicator(size: 20),
                title: Text('正在检索证据并生成分析…'),
              ),
            if (['FAILED', 'STALE', 'CANCELLED'].contains(analysis['state']))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(analysis['error'] as String? ?? '分析已取消，可重新更新'),
                ),
              ),
            if (output.isNotEmpty) ...[
              const SizedBox(height: 16),
              CuteCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      output['summary']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('分析时间：${output['generatedAt']}'),
                    Text('依据：${output['basisQuality']}（不是成功概率）'),
                    if ((output['retrieval'] as Map?)?['degradedReason']
                            ?.toString()
                            .isNotEmpty ==
                        true)
                      Text(
                        (output['retrieval'] as Map)['degradedReason']
                            .toString(),
                      ),
                    TextButton.icon(
                      onPressed: evidence,
                      icon: const Icon(Icons.link),
                      label: const Text('查看 RAG 分析依据'),
                    ),
                  ],
                ),
              ),
              const SectionHeader('经历与成果'),
              for (final fact in entries('facts'))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(fact['text'].toString()),
                    subtitle: Text(
                      '${fact['claimType']} · ${fact['provenance']}',
                    ),
                  ),
                ),
              const SectionHeader('可以验证的方向'),
              for (final direction in entries('directions'))
                Card(
                  child: ListTile(
                    title: Text(direction['text'].toString()),
                    subtitle: Text(
                      '方向推测 · ${(direction['conditions'] as List? ?? []).join('；')}',
                    ),
                  ),
                ),
              if ((output['gaps'] as List? ?? []).isNotEmpty)
                CuteCard(
                  color: const Color(0xFFFFF3DE),
                  child: Text(
                    '还缺哪些信息：\n${(output['gaps'] as List).join('\n')}',
                  ),
                ),
              const SectionHeader('下一步实践建议'),
              for (final suggestion in entries('suggestions'))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(suggestion['text'].toString()),
                        Text('验证方式：${suggestion['validation']}'),
                        TextButton(
                          onPressed: () async {
                            try {
                              await client.call(
                                'POST',
                                '/ai-maps/development/${analysis['id']}/feedback',
                                body: {
                                  'itemKey': suggestion['key'],
                                  'type': 'UNHELPFUL',
                                  'comment': '',
                                },
                                headers: {
                                  'Idempotency-Key':
                                      'feedback-${DateTime.now().microsecondsSinceEpoch}',
                                },
                              );
                              if (mounted) {
                                notice(this.context, '反馈已记录，可调整目标后重新分析');
                              }
                            } catch (e) {
                              if (mounted) notice(this.context, e.toString());
                            }
                          },
                          child: const Text('这条建议不合适'),
                        ),
                      ],
                    ),
                  ),
                ),
            ] else if (!loading && !working)
              const EmptyIllustration(
                title: '让经历成为下一次分析的依据',
                subtitle: '提交日志和成果后，更新分析。数据不足时会说明缺口。',
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: working || loading ? null : generate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('更新分析'),
            ),
          ],
        ],
      ),
    );
  }
}
