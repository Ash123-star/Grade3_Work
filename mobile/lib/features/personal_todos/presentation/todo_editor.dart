import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/state/providers.dart';
import '../../../data/models/models.dart';
import '../../../shared/calendar/civil_date.dart';
import '../../../theme/home_paper_theme.dart';
import '../application/todo_providers.dart';
import '../data/personal_todo.dart';

Future<bool?> showTodoEditor(
  BuildContext context, {
  required String date,
  PersonalTodo? todo,
  bool? completed,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (dialogContext) => Theme(
    data: homePaperTheme(dialogContext),
    child: TodoEditor(date: date, todo: todo, completed: completed),
  ),
);

class TodoEditor extends ConsumerStatefulWidget {
  const TodoEditor({super.key, required this.date, this.todo, this.completed});
  final String date;
  final PersonalTodo? todo;
  final bool? completed;
  @override
  ConsumerState<TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends ConsumerState<TodoEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, note;
  late final Session opened;
  late String date;
  String? id, error;
  int version = 0;
  bool completed = false, busy = false, conflict = false, deleted = false;
  PersonalTodo? latest;
  @override
  void initState() {
    super.initState();
    opened = ref.read(sessionProvider);
    final pending = ref.read(pendingTodoCommandProvider);
    id = pending?.id ?? widget.todo?.id;
    final body = pending?.body;
    date = body?['date'] as String? ?? widget.todo?.date ?? widget.date;
    version = body?['version'] as int? ?? widget.todo?.version ?? 0;
    completed =
        body?['completed'] as bool? ??
        widget.completed ??
        widget.todo?.completed ??
        false;
    title = TextEditingController(
      text: pending?.method == 'DELETE'
          ? '待确认删除的事项'
          : body?['title'] as String? ?? widget.todo?.title ?? '',
    );
    note = TextEditingController(
      text: pending?.method == 'DELETE'
          ? ''
          : body?['note'] as String? ?? widget.todo?.note ?? '',
    );
    if (widget.completed != null && pending == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) save();
      });
    }
  }

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    super.dispose();
  }

  bool get sameSession {
    final current = ref.read(sessionProvider);
    return current.canReadBusiness &&
        current.id == opened.id &&
        current.token == opened.token;
  }

  Future<void> save({bool remove = false}) async {
    if (busy || !sameSession || conflict || deleted) return;
    final pending = ref.read(pendingTodoCommandProvider);
    if (pending == null &&
        !remove &&
        !(form.currentState?.validate() ?? false)) {
      return;
    }
    final command =
        pending ??
        TodoCommand(
          remove
              ? 'DELETE'
              : id == null
              ? 'POST'
              : 'PUT',
          id,
          remove
              ? {'version': version}
              : {
                  'title': title.text.trim(),
                  'note': note.text.trim(),
                  'date': date,
                  if (id != null) ...{
                    'version': version,
                    'completed': completed,
                  },
                },
        );
    ref.read(pendingTodoCommandProvider.notifier).state = command;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(todoRepositoryProvider).execute(command);
      if (!mounted || !sameSession) return;
      ref.read(pendingTodoCommandProvider.notifier).state = null;
      ref.invalidate(todoDayProvider);
      ref.invalidate(todoMonthProvider);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted || !sameSession) return;
      final failure = e is ApiFailure ? e : null;
      final rejected =
          failure != null &&
          [
            FailureKind.validation,
            FailureKind.conflict,
            FailureKind.notFound,
            FailureKind.forbidden,
            FailureKind.unauthorized,
          ].contains(failure.kind);
      if (rejected) ref.read(pendingTodoCommandProvider.notifier).state = null;
      setState(() {
        error = rejected ? '$e' : '保存结果尚未确认。输入已保留，请重试原操作。';
        conflict = failure?.kind == FailureKind.conflict;
        deleted = failure?.kind == FailureKind.notFound;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refreshConflict() async {
    if (id == null || !sameSession) return;
    setState(() => busy = true);
    try {
      final server = await ref.read(todoRepositoryProvider).detail(id!);
      if (!mounted || !sameSession) return;
      setState(() => latest = server);
    } catch (e) {
      if (mounted && sameSession) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionProvider);
    if (!sameSession) {
      return AlertDialog(
        title: const Text('账号权限已变化'),
        content: const Text('请关闭后重新查看。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('关闭'),
          ),
        ],
      );
    }
    final pending = ref.watch(pendingTodoCommandProvider);
    final locked = busy || pending != null || conflict || deleted;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 390),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 22),
        actionsPadding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        scrollable: true,
        title: Text(
          pending?.method == 'DELETE'
              ? '确认删除结果'
              : id == null
              ? '新增事项'
              : '编辑事项',
        ),
        content: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('事项标题'),
                const SizedBox(height: 7),
                TextFormField(
                  key: const ValueKey('todo-title'),
                  controller: title,
                  enabled: !locked,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    hintText: '记录一件自己的事',
                    counterText: '',
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? '请填写事项标题'
                      : (v ?? '').runes.length > 120
                      ? '标题最多120字'
                      : null,
                ),
                const SizedBox(height: 12),
                const Text('日期'),
                const SizedBox(height: 7),
                OutlinedButton.icon(
                  onPressed: locked
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: parseCivilDate(date),
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100, 12, 31),
                          );
                          if (picked != null && mounted && sameSession) {
                            setState(() => date = civilDate(picked));
                          }
                        },
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(date),
                ),
                const SizedBox(height: 12),
                const Text('备注（选填）'),
                const SizedBox(height: 7),
                TextFormField(
                  key: const ValueKey('todo-note'),
                  controller: note,
                  enabled: !locked,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: '补充说明',
                    counterText: '',
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (conflict && latest == null)
                  TextButton(
                    onPressed: busy ? null : refreshConflict,
                    child: const Text('查看服务器最新版本'),
                  ),
                if (latest != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '服务器版本 ${latest!.version}\n${latest!.title}\n${latest!.date}\n${latest!.note}\n${latest!.completed ? '已完成' : '未完成'}',
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            version = latest!.version;
                            latest = null;
                            conflict = false;
                            error = '已采用最新版本号，保留你的输入，请检查后再次保存。';
                          }),
                    child: const Text('保留我的输入，重新编辑'),
                  ),
                ],
                if (pending != null && !busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('关闭后可从首页“继续确认”重试；重试前暂不能修改内容。'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (id != null && pending == null && !deleted)
            TextButton(
              onPressed: locked
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('删除这条事项？'),
                          content: const Text('删除后将从每日事项中移除。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted && sameSession) {
                        await save(remove: true);
                      }
                    },
              child: const Text('删除'),
            ),
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context, false),
            child: Text(pending == null ? '取消' : '稍后确认'),
          ),
          FilledButton(
            onPressed: busy || conflict || deleted ? null : save,
            child: Text(
              busy
                  ? '保存中…'
                  : pending != null
                  ? '重试原操作'
                  : '保存',
            ),
          ),
        ],
      ),
    );
  }
}
