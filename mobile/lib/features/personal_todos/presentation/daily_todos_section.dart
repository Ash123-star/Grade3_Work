import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoTheme,
        CupertinoThemeData,
        CupertinoTextThemeData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/state/providers.dart';
import '../../../shared/calendar/civil_date.dart';
import '../../../shared/generated_assets.dart';
import '../../../theme/home_paper_theme.dart';
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
  List<PersonalTodo> _stableRows = [];
  int? _stableTotal;
  late int _sessionEpoch;
  int _readGeneration = 0;
  bool _repairing = false, _repairScheduled = false, _repairAttempted = false;
  Object? _repairError;
  @override
  void initState() {
    super.initState();
    _sessionEpoch = ref.read(sessionEpochProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _readGeneration++;
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
      _resetPages();
    });
  }

  Future<void> _chooseMonth() async {
    final epoch = ref.read(sessionEpochProvider);
    var month = DateTime(selected.year, selected.month);
    final paper = HomePaperTokens.of(context);
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: paper.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('选择年月', style: paper.heading(18))),
                  TextButton(
                    onPressed: () => Navigator.pop(sheet),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    key: const ValueKey('todo-month-confirm'),
                    onPressed: () => Navigator.pop(sheet, month),
                    child: const Text('确定'),
                  ),
                ],
              ),
              SizedBox(
                height: MediaQuery.sizeOf(sheet).height * .3,
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    primaryColor: paper.green,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: paper.body(20),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    key: const ValueKey('todo-month-wheel'),
                    mode: CupertinoDatePickerMode.monthYear,
                    initialDateTime: month,
                    minimumYear: 1900,
                    maximumYear: 2100,
                    onDateTimeChanged: (value) => month = value,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && picked != null && epoch == ref.read(sessionEpochProvider)) {
      select(DateTime(picked.year, picked.month));
    }
  }

  Future<void> edit({PersonalTodo? todo, bool? completed}) async {
    await showTodoEditor(
      context,
      date: civilDate(selected),
      todo: todo,
      completed: completed,
    );
    if (mounted) setState(_resetPages);
  }

  void _resetPages() {
    _readGeneration++;
    cursors = ['0'];
    _stableRows = [];
    _stableTotal = null;
    _repairing = false;
    _repairScheduled = false;
    _repairAttempted = false;
    _repairError = null;
  }

  String? _pageProblem(List<TodoPage> pages, List<String> positions) {
    if (pages.isEmpty) return null;
    final total = pages.first.total;
    final ids = <String>{};
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (page.total != total ||
          (i > 0 && pages[i - 1].nextCursor != positions[i])) {
        return '事项数量或分页位置已变化';
      }
      for (final item in page.items) {
        if (!ids.add(item.id)) return '事项排序已变化';
      }
      if (ids.length > total) return '事项数量已变化';
    }
    final next = pages.last.nextCursor;
    if ((next == null && ids.length != total) ||
        (next != null && positions.contains(next))) {
      return '事项尚未读取完整';
    }
    return null;
  }

  /// OFFSET pages may move when another client completes or deletes a todo.
  /// Re-read the requested prefix once; never silently deduplicate a moved row.
  Future<void> _repairPages() async {
    if (_repairing) return;
    final generation = ++_readGeneration;
    final epoch = ref.read(sessionEpochProvider);
    final day = civilDate(selected);
    final requestedPages = cursors.length;
    bool active() =>
        mounted &&
        generation == _readGeneration &&
        epoch == ref.read(sessionEpochProvider) &&
        civilDate(selected) == day;
    setState(() {
      _repairing = true;
      _repairScheduled = false;
      _repairAttempted = true;
      _repairError = null;
    });
    final refreshed = <TodoPage>[];
    final positions = <String>[];
    var cursor = '0';
    try {
      for (var i = 0; i < requestedPages; i++) {
        if (!active()) return;
        positions.add(cursor);
        final page = await ref.refresh(todoDayProvider((day, cursor)).future);
        if (!active()) return;
        refreshed.add(page);
        final problem = _pageProblem(refreshed, positions);
        if (problem != null) {
          throw ApiFailure(FailureKind.conflict, '$problem，请重新读取');
        }
        if (page.nextCursor == null) break;
        cursor = page.nextCursor!;
      }
      if (!active()) return;
      ref.invalidate(todoMonthProvider(civilMonth(selected)));
      setState(() {
        cursors = positions;
        _stableRows = refreshed.expand((page) => page.items).toList();
        _stableTotal = refreshed.first.total;
        _repairing = false;
      });
    } catch (error) {
      if (!active()) return;
      setState(() {
        _repairing = false;
        _repairError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final epoch = ref.watch(sessionEpochProvider);
    if (_sessionEpoch != epoch) {
      _sessionEpoch = epoch;
      _resetPages();
    }
    final paper = HomePaperTokens.of(context);
    final month = ref.watch(todoMonthProvider(civilMonth(selected)));
    final pending = ref.watch(pendingTodoCommandProvider);
    final pages = [
      for (final cursor in cursors)
        ref.watch(todoDayProvider((civilDate(selected), cursor))),
    ];
    final complete = pages.every((page) => !page.isLoading && !page.hasError);
    final loaded = [
      for (final page in pages)
        if (!page.isLoading && !page.hasError && page.valueOrNull != null)
          page.valueOrNull!,
    ];
    final problem = complete ? _pageProblem(loaded, cursors) : null;
    if (problem != null && !_repairAttempted && !_repairScheduled) {
      _repairScheduled = true;
      final generation = _readGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _readGeneration) _repairPages();
      });
    }
    final preserving = _repairing || _repairError != null || problem != null;
    if (complete && !preserving) {
      _stableRows = loaded.expand((page) => page.items).toList();
      _stableTotal = pages.first.valueOrNull?.total;
    }
    final rows = [..._stableRows]
      ..sort(
        (a, b) => a.completed == b.completed
            ? 0
            : a.completed
            ? 1
            : -1,
      );
    final seenError = pages.any((p) => p.hasError);
    final next = pages.last.valueOrNull?.nextCursor;
    final total = _stableTotal;
    final selectedCount = !month.isLoading && !month.hasError
        ? ((month.valueOrNull ?? const <String, TodoCount>{})[civilDate(
                selected,
              )] ??
              const TodoCount(0, 0))
        : null;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const DogAvatar(index: DogAssets.friendly, size: 24),
                      const SizedBox(width: 6),
                      Text('每日事项', style: paper.heading(18)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 11,
                        color: paper.muted,
                      ),
                      const SizedBox(width: 4),
                      Text('仅自己可见', style: paper.body(11, color: paper.muted)),
                    ],
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () => edit(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新增事项'),
                style: TextButton.styleFrom(iconAlignment: IconAlignment.start),
              ),
            ],
          ),
        ),
        if (AppConfig.mock)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              '演示事项 · 仅保存在当前演示会话中',
              style: paper.body(11, color: paper.muted),
            ),
          ),
        if (pending != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('有一项保存结果待确认'),
              subtitle: const Text('请先确认原操作，再继续修改事项。'),
              trailing: TextButton(
                onPressed: () => edit(),
                child: const Text('继续确认'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const ValueKey('todo-month-picker'),
                  onPressed: _chooseMonth,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    foregroundColor: paper.ink,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '${selected.year}年 ${selected.month}月',
                          semanticsLabel:
                              '选择年月，${selected.year}年${selected.month}月',
                          style: paper
                              .body(15)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.expand_more, size: 16),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '上个月',
                onPressed: selected.year == 1900 && selected.month == 1
                    ? null
                    : () => select(DateTime(selected.year, selected.month - 1)),
                icon: const Icon(Icons.chevron_left, size: 22),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: TextButton(
                  onPressed: () => select(shanghaiToday()),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: HomePaperTokens.todaySurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '今天',
                      style: paper.body(12, color: HomePaperTokens.orangeInk),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '下个月',
                onPressed: selected.year == 2100 && selected.month == 12
                    ? null
                    : () => select(DateTime(selected.year, selected.month + 1)),
                icon: const Icon(Icons.chevron_right, size: 22),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 3),
          child: Row(
            children: [
              for (final day in ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: paper.body(11, color: paper.muted),
                  ),
                ),
            ],
          ),
        ),
        month.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Text(
                  '月历加载失败：$e',
                  style: paper.body(13, color: HomePaperTokens.error),
                ),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(todoMonthProvider(civilMonth(selected))),
                  child: const Text('重试月历'),
                ),
              ],
            ),
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
                                counts[civilDate(day)] ?? const TodoCount(0, 0),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: paper.line)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    widthFactor: 1,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '数字为待办数 · ✓ 为全部完成',
                      style: paper.body(10, color: paper.muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: paper.line)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 15, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${selected.month}月${selected.day}日${civilDate(selected) == civilDate(shanghaiToday()) ? ' · 今天' : ''}',
                        style: paper.heading(15, height: 1.45),
                      ),
                      if (total != null)
                        Text(
                          selectedCount == null
                              ? '$total件事项'
                              : '${selectedCount.pending}件待办 / $total件事项',
                          style: paper.body(10, color: paper.muted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (rows.isEmpty && !preserving && !seenError && complete)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 8,
                      ),
                      child: Column(
                        children: [
                          Text(
                            '这一天还没有记录事项',
                            style: paper.body(13, color: paper.muted),
                          ),
                          TextButton(
                            onPressed: () => edit(),
                            child: const Text('＋ 新增事项'),
                          ),
                        ],
                      ),
                    ),
                  for (var i = 0; i < rows.length; i++) ...[
                    if (rows[i].completed && (i == 0 || !rows[i - 1].completed))
                      Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 2),
                        child: Text(
                          '已完成 · ${selectedCount?.completed ?? rows.where((t) => t.completed).length}',
                          style: paper.body(11, color: paper.muted),
                        ),
                      ),
                    _TodoRow(
                      todo: rows[i],
                      last: i == rows.length - 1,
                      onEdit: () => edit(todo: rows[i]),
                      onToggle: () =>
                          edit(todo: rows[i], completed: !rows[i].completed),
                    ),
                  ],
                  if (_repairing)
                    const Padding(
                      key: ValueKey('todo-list-repair'),
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(),
                          ),
                          SizedBox(width: 12),
                          Expanded(child: Text('事项列表已变化，正在重新读取…')),
                        ],
                      ),
                    )
                  else if (_repairError != null || problem != null)
                    Column(
                      children: [
                        Text('事项列表已变化，尚未加载完整：${_repairError ?? problem}'),
                        TextButton(
                          key: const ValueKey('retry-todo-list-repair'),
                          onPressed: _repairPages,
                          child: const Text('重新读取事项'),
                        ),
                      ],
                    ),
                  if (!preserving)
                    for (var i = 0; i < pages.length; i++)
                      if (pages[i].isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (pages[i].hasError)
                        Column(
                          children: [
                            Text('事项尚未加载完整：${pages[i].error}'),
                            TextButton(
                              onPressed: () => ref.invalidate(
                                todoDayProvider((
                                  civilDate(selected),
                                  cursors[i],
                                )),
                              ),
                              child: const Text('重试事项'),
                            ),
                          ],
                        ),
                  if (!preserving &&
                      next != null &&
                      !seenError &&
                      !cursors.contains(next))
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _repairAttempted = false;
                        cursors = [...cursors, next];
                      }),
                      child: const Text('加载更多事项'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: HomePaperTokens.sheetShadow,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            key: const ValueKey('daily-todos-paper'),
            color: paper.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: paper.line),
            ),
            child: content,
          ),
        ),
        for (final left in [true, false])
          Positioned(
            top: -7,
            left: left ? 25 : null,
            right: left ? null : 25,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Container(
                  width: 7,
                  height: 13,
                  decoration: BoxDecoration(
                    color: HomePaperTokens.binding,
                    border: Border.all(color: HomePaperTokens.bindingEdge),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.todo,
    required this.last,
    required this.onEdit,
    required this.onToggle,
  });
  final PersonalTodo todo;
  final bool last;
  final VoidCallback onEdit, onToggle;
  @override
  Widget build(BuildContext context) {
    final paper = HomePaperTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: HomePaperTokens.rowLine)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Semantics(
                button: true,
                checked: todo.completed,
                label: '${todo.completed ? '恢复未完成' : '标记完成'}：${todo.title}',
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: todo.completed ? HomePaperTokens.mint : null,
                            border: Border.all(
                              color: todo.completed
                                  ? HomePaperTokens.completedEdge
                                  : HomePaperTokens.checkEdge,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: todo.completed
                              ? Icon(Icons.check, size: 13, color: paper.green)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          todo.title,
                          style: paper
                              .body(
                                15,
                                height: 1.65,
                                color: todo.completed ? paper.muted : paper.ink,
                              )
                              .copyWith(
                                fontWeight: FontWeight.w500,
                                decoration: todo.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                        if (todo.note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              todo.note,
                              style: paper.body(
                                12,
                                height: 1.7,
                                color: paper.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '编辑或删除：${todo.title}',
                onPressed: onEdit,
                icon: Icon(Icons.more_horiz, size: 20, color: paper.muted),
              ),
            ],
          ),
        ),
      ),
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
    final paper = HomePaperTokens.of(context);
    final today = civilDate(day) == civilDate(shanghaiToday());
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${civilDate(day)}${today ? ' 今天' : ''}，${count.pending}项未完成，${count.completed}项已完成',
      excludeSemantics: true,
      child: InkWell(
        onTap: day.year < 1900 || day.year > 2100 ? null : onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: large ? 60 : 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: large ? 35 : 30,
                  constraints: BoxConstraints(minHeight: large ? 34 : 29),
                  decoration: BoxDecoration(
                    color: selected ? paper.accent : null,
                    borderRadius: BorderRadius.circular(10),
                    border: today && !selected
                        ? Border.all(
                            color: HomePaperTokens.todayEdge,
                            width: 1.5,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${day.day}',
                    style: paper
                        .body(
                          14,
                          height: 1.2,
                          color: selected
                              ? HomePaperTokens.accentInk
                              : currentMonth
                              ? paper.ink
                              : HomePaperTokens.outside,
                        )
                        .copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                  ),
                ),
                SizedBox(
                  height: large ? 18 : 13,
                  child: Text(
                    count.pending > 0
                        ? '${count.pending}'
                        : count.total > 0
                        ? '✓'
                        : '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: paper.body(
                      10,
                      height: 1.3,
                      color: selected ? HomePaperTokens.orangeInk : paper.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
