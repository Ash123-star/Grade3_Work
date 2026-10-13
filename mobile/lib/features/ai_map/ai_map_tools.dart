import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/ai.dart';
import 'package:pandora_mobile/data/repositories/ai_repository.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'server_ai_page.dart';
import 'graph_layout.dart';

Color graphForeground(BuildContext context, dynamic type) => switch (type) {
  'GOAL' => const Color(0xFFA7460E),
  'RESULT' => const Color(0xFF246447),
  'BLOCKER' => const Color(0xFF275E8D),
  _ => const Color(0xFF7650B6),
};

class ServerAiUsagePage extends ConsumerStatefulWidget {
  const ServerAiUsagePage({super.key});
  @override
  ConsumerState<ServerAiUsagePage> createState() => _ServerAiUsagePageState();
}

class _ServerAiUsagePageState extends AiProtectedState<ServerAiUsagePage> {
  Map<String, dynamic>? usage;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void clearProtected() {
    usage = null;
  }

  Future<void> load() async {
    if (!alive) return;
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await repo.usage(token: token);
      aiObjects(value['usage'], max: 30);
      if (value['dailyLimit'] is! num) {
        throw const ApiFailure(FailureKind.server, 'AI预算未提供');
      }
      if (alive && !token.isCancelled) setState(() => usage = value);
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive && !token.isCancelled) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!guard()) return deniedPage();
    return PageFrame(
      title: 'AI用量',
      child: PageBody(
        children: [
          if (loading) const LoadingSkeleton(),
          if (error != null) ErrorPanel(error!, retry: load),
          if (usage != null) ...[
            PaperSurface(
              color: const Color(0xFFFFF0DA),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('本人每日预算'),
                  Text(
                    '${usage!['dailyLimit']} tokens',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('按UTC业务日期统计，取消或失败的请求也可能计入实际用量。'),
            const SizedBox(height: 16),
            for (final row in aiObjects(usage!['usage'], max: 30))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${row['date']}'),
                subtitle: Text('${row['jobs']} 次作业'),
                trailing: Text('${row['tokens']} tokens'),
              ),
            if ((usage!['usage'] as List).isEmpty) const Text('暂无用量记录'),
          ],
        ],
      ),
    );
  }
}

class ServerAiGraphPage extends ConsumerStatefulWidget {
  const ServerAiGraphPage({super.key});
  @override
  ConsumerState<ServerAiGraphPage> createState() => _ServerAiGraphPageState();
}

class _ServerAiGraphPageState extends AiProtectedState<ServerAiGraphPage> {
  List<Map<String, dynamic>> nodes = [], edges = [];
  Map<String, AiJob> jobs = {};
  String search = '', type = '全部';
  bool loading = true, saving = false;
  String? sourceId, targetId;
  final label = TextEditingController();
  final searchController = TextEditingController();
  final transform = TransformationController();
  RelationshipLayout get graph => RelationshipLayout.build(
    nodes,
    edges,
    textScale: MediaQuery.textScalerOf(context).scale(16) / 16,
  );
  void fitGraph() {
    final scale = ((MediaQuery.sizeOf(context).width - 32) / graph.size.width)
        .clamp(.4, 1.0);
    transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void clearProtected() {
    nodes = [];
    edges = [];
    jobs = {};
    sourceId = null;
    targetId = null;
    label.clear();
    searchController.clear();
  }

  @override
  void dispose() {
    label.dispose();
    searchController.dispose();
    transform.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!alive) return;
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await repo.map(token: token);
      final fetched = aiObjects(value['nodes']);
      final related = <String, AiJob>{};
      for (final id in fetched.map((n) => '${n['job_id'] ?? ''}').toSet()) {
        if (!alive || token.isCancelled) return;
        if (id.isEmpty) throw const ApiFailure(FailureKind.server, '节点作业来源未提供');
        final job = await repo.job(id, token: token);
        if (job.data['owner_id'] != originalAccount.id) {
          throw const ApiFailure(FailureKind.forbidden, '节点来源已失去权限');
        }
        related[id] = job;
      }
      final uniqueIds = <String>{};
      for (final node in fetched) {
        node['body'] = aiObject(node['body']);
        if (node['id'] is! String ||
            (node['id'] as String).trim().isEmpty ||
            !uniqueIds.add(node['id'] as String) ||
            node['body']['title'] is! String ||
            (node['body']['title'] as String).trim().isEmpty ||
            ![
              'GOAL',
              'RESULT',
              'BLOCKER',
              'RISK',
            ].contains(node['body']['type'])) {
          throw const ApiFailure(FailureKind.server, '地图节点格式未确认，请重新读取');
        }
        if (node['owner_id'] != originalAccount.id ||
            !related['${node['job_id']}']!.validRefs(
              node['body']['sourceIds'],
              originalAccount.id,
            )) {
          throw const ApiFailure(FailureKind.forbidden, '节点来源不可用，请重新确认权限');
        }
      }
      final ids = fetched.map((n) => n['id']).toSet();
      final fetchedEdges = aiObjects(value['edges'])
          .where(
            (e) => ids.contains(e['source_id']) && ids.contains(e['target_id']),
          )
          .toList();
      if (alive && !token.isCancelled) {
        setState(() {
          nodes = fetched;
          edges = fetchedEdges;
          jobs = related;
          if (!ids.contains(sourceId)) sourceId = null;
          if (!ids.contains(targetId)) targetId = null;
        });
        if (mounted) fitGraph();
      }
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive && !token.isCancelled) setState(() => loading = false);
    }
  }

  Future<void> addEdge() async {
    if (!alive || saving || sourceId == null || targetId == null) return;
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await repo.edge(sourceId!, targetId!, label.text.trim(), token: token);
      if (alive && !token.isCancelled) {
        if (mounted) notice(context, '关系已保存', success: true);
        await load();
      }
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive) setState(() => saving = false);
    }
  }

  Future<void> analyzeSource(AiJob job, String purpose, String source) async {
    if (!alive || saving) return;
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final created = await repo.create(
        '${job.input['date']}',
        '${job.input['period']}',
        purpose: purpose,
        focus: source,
        token: token,
      );
      if (!alive || token.isCancelled) return;
      ref.read(latestAiJobProvider(originalAccount.id).notifier).state =
          created.id;
      if (mounted) context.go('/ai');
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive && !token.isCancelled) setState(() => saving = false);
    }
  }

  void nodeDetails(Map<String, dynamic> node) {
    final job = jobs['${node['job_id']}']!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Consumer(
        builder: (sheet, ref, _) {
          final session = ref.watch(sessionProvider);
          if (session.id != originalAccount.id ||
              session.token != originalAccount.token ||
              !session.canReadBusiness) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('节点访问已停止，请重新确认账号与权限'),
              ),
            );
          }
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${node['body']['title']}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('节点属于建议草稿，风险与影响需人工核实。'),
                    const SizedBox(height: 16),
                    const Text(
                      '原始依据',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    AiSources(
                      job,
                      node['body']['sourceIds'],
                      onPurpose: (purpose, source) {
                        Navigator.pop(sheet);
                        analyzeSource(job, purpose, source);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '相关下一步',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Text('来自同一作业、共享依据的建议；查看建议不会创建任务。'),
                    if (!job.actions.any(
                      (action) => aiIds(action['sourceIds']).any(
                        (id) => aiIds(node['body']['sourceIds']).contains(id),
                      ),
                    ))
                      const Text('当前作业没有共享依据的行动建议。'),
                    for (final (index, action) in job.actions.indexed)
                      if (aiIds(action['sourceIds']).any(
                        (id) => aiIds(node['body']['sourceIds']).contains(id),
                      ))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${action['title']}'),
                          subtitle: const Text('查看依据与人工确认条件'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(sheet);
                            context.push(
                              '/ai/jobs/${encode(job.id)}/actions/$index',
                            );
                          },
                        ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(sheet);
                        context.push('/ai/jobs/${encode(job.id)}/edit');
                      },
                      child: const Text('编辑所属建议草稿'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!guard()) return deniedPage();
    final visible = nodes
        .where(
          (n) =>
              '${n['body']['title']}'.contains(search) &&
              (type == '全部' || n['body']['type'] == type),
        )
        .toList();
    final layout = graph;
    final visibleIds = visible.map((n) => n['id']).toSet();
    final visibleEdges = edges
        .where(
          (e) =>
              visibleIds.contains(e['source_id']) &&
              visibleIds.contains(e['target_id']),
        )
        .toList();
    String contextLabel(Map<String, dynamic> node) {
      final id = node['id'];
      return '${graphTypeLabel(node['body']['type'])}'
          '${layout.cyclic.contains(id) ? ' · 循环依赖' : ''}'
          '${layout.isolated.contains(id) ? ' · 未关联' : ''}';
    }

    return PageFrame(
      title: '工作关系图',
      actions: [
        IconButton(
          onPressed: loading ? null : load,
          tooltip: '刷新地图',
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: PageBody(
        children: [
          Text(aiScope(originalAccount)),
          const Text('箭头从前置指向后续节点；关系来自已有作业，未关联节点独立展示。可拖动、缩放或使用下方列表。'),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: '搜索节点',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final (value, name) in [
                ('全部', '全部'),
                ('GOAL', '目标'),
                ('RESULT', '成果'),
                ('BLOCKER', '阻碍'),
                ('RISK', '风险'),
              ])
                ChoiceChip(
                  label: Text(name),
                  selected: type == value,
                  onSelected: (_) => setState(() => type = value),
                ),
            ],
          ),
          if (loading) const LoadingSkeleton(),
          if (error != null) ErrorPanel(error!, retry: load),
          if (!loading && nodes.isEmpty && error == null)
            const Text('尚无有权访问的地图节点，请先生成分析。'),
          if (!loading && nodes.isNotEmpty && visible.isEmpty) ...[
            const Text('没有匹配的节点，请调整搜索或类型。'),
            TextButton(
              onPressed: () => setState(() {
                search = '';
                type = '全部';
                searchController.clear();
              }),
              child: const Text('清除地图筛选'),
            ),
          ],
          if (visible.isNotEmpty) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final kind in ['GOAL', 'RESULT', 'BLOCKER', 'RISK'])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: graphForeground(context, kind),
                      ),
                      const SizedBox(width: 4),
                      Text(graphTypeLabel(kind)),
                    ],
                  ),
              ],
            ),
            if (layout.cyclic.any(visibleIds.contains))
              const Text('存在循环依赖：同组节点互相依赖，请在列表核对方向。'),
            if (search.isNotEmpty || type != '全部')
              const Text('仅显示筛选内的节点和关系；筛选不会删除已有关系。'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: fitGraph, child: const Text('重置缩放')),
            ),
            SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ColoredBox(
                  color: const Color(0xFFFFF0DA),
                  child: InteractiveViewer(
                    transformationController: transform,
                    constrained: false,
                    minScale: .4,
                    maxScale: 2,
                    boundaryMargin: const EdgeInsets.all(120),
                    child: SizedBox(
                      width: layout.size.width,
                      height: layout.size.height,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _EdgesPainter(
                                layout,
                                visibleEdges,
                                Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (final node in visible)
                            Positioned(
                              left: layout.points[node['id']]!.dx,
                              top: layout.points[node['id']]!.dy,
                              width: layout.nodeSize.width,
                              height: layout.nodeSize.height,
                              child: Semantics(
                                button: true,
                                label:
                                    '${contextLabel(node)}：${node['body']['title']}，打开来源与行动',
                                child: PaperSurface(
                                  color: switch (node['body']['type']) {
                                    'GOAL' => Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    'RESULT' => SunnyPaperTokens.of(
                                      context,
                                    ).success,
                                    'BLOCKER' => SunnyPaperTokens.of(
                                      context,
                                    ).information,
                                    _ => SunnyPaperTokens.of(context).ai,
                                  },
                                  onTap: () => nodeDetails(node),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        contextLabel(node),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: graphForeground(
                                            context,
                                            node['body']['type'],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: Text(
                                          '${node['body']['title']}',
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '依据 ${aiIds(node['body']['sourceIds']).length} 条 · 查看',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '节点列表 · 与关系图相同内容',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            for (final node in visible)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${node['body']['title']}'),
                subtitle: Text(
                  '${contextLabel(node)} · 依据 ${aiIds(node['body']['sourceIds']).length} 条',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => nodeDetails(node),
              ),
            const Divider(height: 24),
            const Text('已有依赖关系', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final edge in visibleEdges)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${nodes.firstWhere((n) => n['id'] == edge['source_id'])['body']['title']} → ${nodes.firstWhere((n) => n['id'] == edge['target_id'])['body']['title']} · ${aiObject(edge['body'])['label'] ?? ''}',
                ),
              ),
            if (visibleEdges.isEmpty)
              Text(search.isNotEmpty || type != '全部' ? '筛选内暂无依赖关系' : '暂无依赖关系'),
            const Divider(height: 24),
            const Text('添加依赖', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final isSource in [true, false])
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    '${isSource ? sourceId : targetId}:${nodes.length}',
                  ),
                  initialValue: isSource ? sourceId : targetId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: isSource ? '前置节点' : '后续节点',
                  ),
                  items: nodes
                      .map(
                        (n) => DropdownMenuItem<String>(
                          value: '${n['id']}',
                          child: Text(
                            '${n['body']['title']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (v) => setState(() {
                          if (isSource) {
                            sourceId = v;
                          } else {
                            targetId = v;
                          }
                        }),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: label,
              maxLength: 200,
              decoration: const InputDecoration(labelText: '关系说明'),
            ),
            SunnyPrimaryButton(
              onPressed:
                  saving ||
                      sourceId == null ||
                      targetId == null ||
                      sourceId == targetId
                  ? null
                  : addEdge,
              child: Text(saving ? '正在保存…' : '保存依赖关系'),
            ),
            if (sourceId != null && sourceId == targetId)
              const Text('节点不能依赖自身'),
          ],
        ],
      ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter(this.layout, this.edges, this.color);
  final RelationshipLayout layout;
  final List<Map<String, dynamic>> edges;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (final edge in edges) {
      final start = layout.points[edge['source_id']],
          end = layout.points[edge['target_id']];
      if (start == null || end == null) continue;
      final width = layout.nodeSize.width, height = layout.nodeSize.height;
      if (start == end) {
        // Existing self edges remain visible, never divide by zero.
        canvas.drawArc(
          Rect.fromLTWH(start.dx + width - 16, start.dy - 24, 40, 56),
          -1.6,
          4.5,
          false,
          paint..style = PaintingStyle.stroke,
        );
        paint.style = PaintingStyle.fill;
        continue;
      }
      final vertical = end.dy != start.dy;
      final a = vertical
          ? start + Offset(width / 2, end.dy > start.dy ? height : 0)
          : start + Offset(end.dx > start.dx ? width : 0, height / 2);
      final b = vertical
          ? end + Offset(width / 2, end.dy > start.dy ? -8 : height + 8)
          : end + Offset(end.dx > start.dx ? -8 : width + 8, height / 2);
      final direction = (b - a) / (b - a).distance;
      final perpendicular = Offset(-direction.dy, direction.dx);
      if (vertical) {
        final middle = (a.dy + b.dy) / 2;
        canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..cubicTo(a.dx, middle, b.dx, middle, b.dx, b.dy),
          paint..style = PaintingStyle.stroke,
        );
        paint.style = PaintingStyle.fill;
      } else {
        canvas.drawLine(a, b, paint);
      }
      canvas.drawPath(
        Path()
          ..moveTo(b.dx, b.dy)
          ..lineTo(
            (b - direction * 10 + perpendicular * 5).dx,
            (b - direction * 10 + perpendicular * 5).dy,
          )
          ..lineTo(
            (b - direction * 10 - perpendicular * 5).dx,
            (b - direction * 10 - perpendicular * 5).dy,
          )
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.edges != edges ||
      oldDelegate.color != color;
}
