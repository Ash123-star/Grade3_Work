import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config.dart';
import '../../../shared/calendar/civil_date.dart';
import '../application/todo_providers.dart';
import '../data/personal_todo.dart';
import 'todo_editor.dart';

class DailyTodosSection extends ConsumerStatefulWidget {
  const DailyTodosSection({super.key});
  @override
  ConsumerState<DailyTodosSection> createState() => _DailyTodosSectionState();
}

class _DailyTodosSectionState extends ConsumerState<DailyTodosSection>
    with WidgetsBindingObserver {
  DateTime selected = shanghaiToday();
  List<String> cursors = ['0'];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(todoMonthProvider);
      ref.invalidate(todoDayProvider);
    }
  }

  void select(DateTime date) {
    if (date.year < 1900 || date.year > 2100) return;
    setState(() {
      selected = date;
      cursors = ['0'];
    });
  }

  Future<void> edit({PersonalTodo? todo, bool? completed}) async {
    await showTodoEditor(
      context,
      date: civilDate(selected),
      todo: todo,
      completed: completed,
    );
    if (mounted) setState(() => cursors = ['0']);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final month = ref.watch(todoMonthProvider(civilMonth(selected)));
    final pending = ref.watch(pendingTodoCommandProvider);
    final pages = [
      for (final cursor in cursors)
        ref.watch(todoDayProvider((civilDate(selected), cursor))),
    ];
    final items = <String, PersonalTodo>{};
    for (final page in pages) {
      if (page.isLoading || page.hasError) continue;
      for (final t in page.valueOrNull?.items ?? <PersonalTodo>[]) {
        items[t.id] = t;
      }
    }
    final rows = items.values.toList()
      ..sort(
        (a, b) => a.completed == b.completed
            ? 0
            : a.completed
            ? 1
            : -1,
      );
    final seenError = pages.any((p) => p.hasError);
    final next = pages.last.valueOrNull?.nextCursor;
    final total = pages.first.valueOrNull?.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('每日事项', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '安排自己的每一天 · 仅自己可见',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('事项'),
            ),
          ],
        ),
        if (AppConfig.mock)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('演示事项 · 仅保存在当前演示会话中'),
          ),
        if (pending != null)
          Card(
            child: ListTile(
              title: const Text('有一项保存结果待确认'),
              subtitle: const Text('请先确认原操作，再继续修改事项。'),
              trailing: TextButton(
                onPressed: () => edit(),
                child: const Text('继续确认'),
              ),
            ),
          ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '上个月',
                      onPressed: selected.year == 1900 && selected.month == 1
                          ? null
                          : () => select(
                              DateTime(selected.year, selected.month - 1),
                            ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${selected.year}年 ${selected.month}月',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: '下个月',
                      onPressed: selected.year == 2100 && selected.month == 12
                          ? null
                          : () => select(
                              DateTime(selected.year, selected.month + 1),
                            ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    TextButton(
                      onPressed: () => select(shanghaiToday()),
                      child: const Text('今天'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final day in ['一', '二', '三', '四', '五', '六', '日'])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            day,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                  ],
                ),
                month.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                  error: (e, _) => Column(
                    children: [
                      Text('月历加载失败：$e'),
                      TextButton(
                        onPressed: () => ref.invalidate(
                          todoMonthProvider(civilMonth(selected)),
                        ),
                        child: const Text('重试月历'),
                      ),
                    ],
                  ),
                  data: (counts) {
                    final days = monthDays(selected);
                    return Column(
                      children: [
                        for (var week = 0; week < days.length; week += 7)
                          Row(
                            children: [
                              for (final day in days.skip(week).take(7))
                                Expanded(
                                  child: _DayCell(
                                    day: day,
                                    selected: day == selected,
                                    count:
                                        counts[civilDate(day)] ??
                                        const TodoCount(0, 0),
                                    currentMonth: day.month == selected.month,
                                    onTap: () => select(day),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
                const Divider(),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      '数字为待办数 · ✓为全部完成',
                      style: TextStyle(fontSize: 11),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: selected,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2100, 12, 31),
                        );
                        if (d != null && mounted) select(d);
                      },
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: const Text('选择日期'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              '${selected.month}月${selected.day}日${civilDate(selected) == civilDate(shanghaiToday()) ? ' · 今天' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (total != null)
              Text('$total件事项', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty && !seenError && pages.every((p) => p.hasValue))
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text('这一天，留给想做的事。'),
                TextButton(
                  onPressed: () => edit(),
                  child: const Text('添加一件小事'),
                ),
              ],
            ),
          ),
        for (final todo in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: todo.completed,
                    semanticLabel:
                        '${todo.completed ? '恢复未完成' : '标记完成'}：${todo.title}',
                    onChanged: (_) =>
                        edit(todo: todo, completed: !todo.completed),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => edit(todo: todo),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              todo.title,
                              style: TextStyle(
                                decoration: todo.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (todo.note.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  todo.note,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            Text(
                              todo.completed ? '已完成' : '未完成',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '编辑或删除：${todo.title}',
                    onPressed: () => edit(todo: todo),
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
            ),
          ),
        for (var i = 0; i < pages.length; i++)
          if (pages[i].isLoading)
            const Center(child: CircularProgressIndicator())
          else if (pages[i].hasError)
            Column(
              children: [
                Text('事项尚未加载完整：${pages[i].error}'),
                TextButton(
                  onPressed: () => ref.invalidate(
                    todoDayProvider((civilDate(selected), cursors[i])),
                  ),
                  child: const Text('重试事项'),
                ),
              ],
            ),
        if (next != null && !seenError && !cursors.contains(next))
          OutlinedButton(
            onPressed: () => setState(() => cursors = [...cursors, next]),
            child: const Text('加载更多事项'),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.count,
    required this.currentMonth,
    required this.onTap,
  });
  final DateTime day;
  final bool selected, currentMonth;
  final TodoCount count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = civilDate(day) == civilDate(shanghaiToday());
    final foreground = selected
        ? colors.onPrimary
        : currentMonth
        ? colors.onSurface
        : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${civilDate(day)}${today ? ' 今天' : ''}，${count.pending}项未完成，${count.completed}项已完成',
      excludeSemantics: true,
      child: InkWell(
        onTap: day.year < 1900 || day.year > 2100 ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: BoxConstraints(
            minHeight: 54 * MediaQuery.textScalerOf(context).scale(1),
          ),
          margin: const EdgeInsets.all(1),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected ? colors.primary : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  color: foreground,
                  fontWeight: today ? FontWeight.bold : null,
                  decoration: today ? TextDecoration.underline : null,
                ),
              ),
              Text(
                count.pending > 0
                    ? '${count.pending}'
                    : count.total > 0
                    ? '✓'
                    : ' ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
