import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/ai_work.dart';
import 'package:pandora_mobile/data/repositories/ai_work_repository.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'work_management_pages.dart' show WorkTargetPicker;

class WorkbenchPage extends ConsumerStatefulWidget {
  const WorkbenchPage({super.key});
  @override
  ConsumerState<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends ConsumerState<WorkbenchPage>
    with WidgetsBindingObserver {
  final input = TextEditingController();
  final inputFocus = FocusNode();
  Timer? timer;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<Session>(sessionProvider, (before, after) {
      if (before?.id != after.id ||
          before?.token != after.token ||
          !after.canReadBusiness) {
        input.clear();
        inputFocus.unfocus();
      }
    });
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted &&
          foreground &&
          TickerMode.of(context) &&
          ref
                  .read(workListProvider)
                  .valueOrNull
                  ?.items
                  .any((e) => e.processing) ==
              true) {
        ref.invalidate(workListProvider);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) ref.invalidate(workListProvider);
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final data = ref.watch(workListProvider);
    final caps = ref.watch(workCapabilitiesProvider);
    return WorkMotionScope(
      child: Scaffold(
        backgroundColor: SunnyPalette.paper,
        appBar: AppBar(
          title: const Text('AI地图'),
          actions: [
            IconButton(
              tooltip: '办事设置',
              onPressed: () => context.push('/ai/work-settings'),
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(workCapabilitiesProvider);
                    ref.invalidate(workListProvider);
                    await ref.read(workListProvider.future);
                  },
                  child: data.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 80),
                        const Icon(Icons.cloud_off_rounded, size: 42),
                        const SizedBox(height: 20),
                        Text(workError(e), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Center(
                          child: OutlinedButton(
                            onPressed: () => ref.invalidate(workListProvider),
                            child: const Text('重新连接'),
                          ),
                        ),
                      ],
                    ),
                    data: (page) => page.items.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              const SizedBox(height: 70),
                              const Icon(
                                Icons.auto_awesome_rounded,
                                color: SunnyPalette.primaryStrong,
                                size: 46,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                '把事情交给我',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontFamily: AppTypography.displayFamily,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 28),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final example in [
                                    '截图建任务',
                                    '检查交付',
                                    '找制度和模板',
                                  ])
                                    ActionChip(
                                      label: Text(example),
                                      onPressed: () {
                                        input.text = switch (example) {
                                          '截图建任务' => '请根据材料整理任务',
                                          '检查交付' => '请帮我检查交付材料',
                                          _ => '请帮我查找',
                                        };
                                        inputFocus.requestFocus();
                                      },
                                    ),
                                ],
                              ),
                            ],
                          )
                        : ListView(
                            key: PageStorageKey(
                              'work-${session.id}:${session.token}',
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              for (final group in [
                                (
                                  '需要你处理',
                                  page.items
                                      .where(
                                        (e) => [
                                          'WAITING_INPUT',
                                          'WAITING_CONFIRMATION',
                                          'PARTIAL',
                                          'FAILED',
                                        ].contains(e.state),
                                      )
                                      .toList(),
                                ),
                                (
                                  '正在办理',
                                  page.items
                                      .where(
                                        (e) =>
                                            e.processing ||
                                            e.state == 'WAITING_REVIEW',
                                      )
                                      .toList(),
                                ),
                                (
                                  '最近办过',
                                  page.items
                                      .where(
                                        (e) => [
                                          'SUCCEEDED',
                                          'CANCELLED',
                                        ].contains(e.state),
                                      )
                                      .toList(),
                                ),
                              ])
                                if (group.$2.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      18,
                                      4,
                                      12,
                                    ),
                                    child: Text(
                                      group.$1,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  for (final item in group.$2)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: _WorkTile(
                                        item,
                                        onTap: () => context.push(
                                          '/ai/work/${Uri.encodeComponent(item.id)}',
                                        ),
                                      ),
                                    ),
                                ],
                              if (page.nextCursor >= 0)
                                TextButton(
                                  onPressed: () => ref
                                      .read(workPageCountProvider.notifier)
                                      .state++,
                                  child: const Text('查看更多事项'),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
              if (!session.canReadBusiness)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('你目前无法办理这项操作'),
                )
              else if (caps.hasError)
                TextButton(
                  onPressed: () => ref.invalidate(workCapabilitiesProvider),
                  child: Text(workError(caps.error!)),
                )
              else if (!caps.hasValue)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                )
              else if (caps.valueOrNull?.enabled == false)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('AI 办事暂时不可用，任务和日志仍可使用'),
                ),
              if (session.canReadBusiness && caps.hasValue)
                WorkComposer(
                  key: ValueKey(
                    '${session.id}:${session.token}:${session.canReadBusiness}',
                  ),
                  controller: input,
                  enabled:
                      !caps.hasError &&
                      !caps.isLoading &&
                      caps.valueOrNull?.enabled == true,
                  focus: inputFocus,
                  onSend: (text, files, key) async {
                    final account = ref.read(sessionProvider);
                    final item = await ref
                        .read(workRepositoryProvider)
                        .create(text, files, key);
                    if (!context.mounted ||
                        !ref.read(sessionProvider).canReadBusiness ||
                        ref.read(sessionProvider).id != account.id ||
                        ref.read(sessionProvider).token != account.token) {
                      return;
                    }
                    ref.invalidate(workListProvider);
                    unawaited(
                      context.push<void>(
                        '/ai/work/${Uri.encodeComponent(item.id)}',
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkTile extends StatelessWidget {
  const _WorkTile(this.item, {required this.onTap});
  final WorkItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PaperSurface(
    color: item.processing ? SunnyPalette.purple : SunnyPalette.surface,
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (item.processing) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(fontSize: 15, color: SunnyPalette.ink),
              ),
            ),
          ],
        ),
        if ('${item.result['summary'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${item.result['summary']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    ),
  );
}

typedef WorkSend =
    Future<void> Function(String text, List<String> files, String key);

class WorkComposer extends ConsumerStatefulWidget {
  const WorkComposer({
    super.key,
    required this.onSend,
    this.controller,
    this.focus,
    this.requestContext,
    this.enabled = true,
  });
  final WorkSend onSend;
  final TextEditingController? controller;
  final FocusNode? focus;
  final String? requestContext;
  final bool enabled;
  @override
  ConsumerState<WorkComposer> createState() => _WorkComposerState();
}

class _WorkComposerState extends ConsumerState<WorkComposer> {
  late final local = widget.controller ?? TextEditingController();
  AttachmentSelection selection = const AttachmentSelection([], ready: true);
  bool attaching = false, busy = false;
  String? error;
  String? requestKey, requestSignature;
  int uploadGeneration = 0;
  @override
  void dispose() {
    if (widget.controller == null) local.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy ||
        !widget.enabled ||
        !ref.read(sessionProvider).canReadBusiness ||
        !selection.ready ||
        local.text.trim().isEmpty && selection.files.isEmpty) {
      return;
    }
    if (selection.files.length > 5 ||
        selection.files.fold<int>(0, (sum, file) => sum + file.size) >
            30 * 1024 * 1024) {
      setState(() => error = '一次最多添加5份材料，总大小不超过30MB');
      return;
    }
    final text = local.text.trim(),
        files = selection.files.map((f) => f.id).toList();
    final signature = jsonEncode([widget.requestContext, text, files]);
    if (signature != requestSignature) {
      requestKey = AiWorkRepository.key();
      requestSignature = signature;
    }
    final session = ref.read(sessionProvider);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSend(text, files, requestKey!);
      if (!mounted ||
          !ref.read(sessionProvider).canReadBusiness ||
          ref.read(sessionProvider).id != session.id ||
          ref.read(sessionProvider).token != session.token) {
        return;
      }
      setState(() {
        local.clear();
        selection = const AttachmentSelection([], ready: true);
        attaching = false;
        uploadGeneration++;
        requestKey = null;
        requestSignature = null;
      });
    } catch (e) {
      if (mounted &&
          ref.read(sessionProvider).id == session.id &&
          ref.read(sessionProvider).token == session.token) {
        setState(() => error = workError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(
      color: SunnyPalette.paper,
      border: Border(top: BorderSide(color: Color(0xFFE1EEE7))),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              liveRegion: true,
              child: Text(error!, style: const TextStyle(fontSize: 15)),
            ),
          ),
        AnimatedSize(
          duration: WorkMotion.duration(context),
          alignment: Alignment.bottomCenter,
          child: Offstage(
            offstage: !attaching,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: AttachmentEditor(
                  aiWork: true,
                  key: ValueKey(uploadGeneration),
                  enabled: !busy && widget.enabled,
                  onChanged: (value) {
                    if (mounted) setState(() => selection = value);
                  },
                ),
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: '添加图片或文件',
              onPressed: busy || !widget.enabled
                  ? null
                  : () => setState(() => attaching = !attaching),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: local,
                focusNode: widget.focus,
                enabled: widget.enabled,
                readOnly: busy,
                minLines: 1,
                maxLines: 4,
                maxLength: 10000,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: '说说要办什么…',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              height: 48,
              child: FilledButton(
                onPressed: busy || !widget.enabled || !selection.ready
                    ? null
                    : send,
                style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('发送'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class WorkDetailPage extends ConsumerStatefulWidget {
  const WorkDetailPage(this.id, {super.key});
  final String id;
  @override
  ConsumerState<WorkDetailPage> createState() => _WorkDetailPageState();
}

class _WorkDetailPageState extends ConsumerState<WorkDetailPage>
    with WidgetsBindingObserver {
  final input = TextEditingController();
  final focus = FocusNode();
  WorkItem? item;
  String? selectedOwnerId;
  Map<String, dynamic>? selectedTask;
  Object? error;
  bool busy = false, loading = false, foreground = true;
  bool pendingLoad = false, accessLost = false, accountChanged = false;
  int generation = 0;
  Timer? timer;
  String commandKey = AiWorkRepository.key();
  String? commandSignature;
  bool current(int ticket) =>
      mounted &&
      ticket == generation &&
      !accountChanged &&
      !accessLost &&
      ref.read(sessionProvider).canReadBusiness;

  void failed(Object failure) {
    setState(() {
      error = failure;
      if (failure is ApiFailure &&
          [
            FailureKind.unauthorized,
            FailureKind.forbidden,
            FailureKind.notFound,
          ].contains(failure.kind)) {
        generation++;
        accessLost = true;
        busy = false;
        item = null;
        selectedOwnerId = null;
        selectedTask = null;
        input.clear();
        focus.unfocus();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (foreground &&
          mounted &&
          !accessLost &&
          !accountChanged &&
          TickerMode.of(context)) {
        unawaited(load());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) unawaited(load());
  }

  @override
  void didUpdateWidget(covariant WorkDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id == widget.id) return;
    generation++;
    item = null;
    error = null;
    accessLost = false;
    selectedOwnerId = null;
    selectedTask = null;
    input.clear();
    commandSignature = null;
    busy = false;
    unawaited(load());
  }

  @override
  void dispose() {
    timer?.cancel();
    input.dispose();
    focus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    if (accountChanged) return;
    if (loading || busy) {
      pendingLoad = true;
      return;
    }
    loading = true;
    final session = ref.read(sessionProvider), ticket = generation;
    try {
      final next = await ref.read(workRepositoryProvider).get(widget.id);
      if (mounted &&
          ticket == generation &&
          ref.read(sessionProvider).id == session.id &&
          ref.read(sessionProvider).token == session.token &&
          (item == null || next.version >= item!.version)) {
        setState(() {
          item = next;
          accessLost = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted &&
          ticket == generation &&
          ref.read(sessionProvider).id == session.id &&
          ref.read(sessionProvider).token == session.token) {
        failed(e);
      }
    } finally {
      loading = false;
      if (pendingLoad && mounted && !accessLost && !accountChanged) {
        pendingLoad = false;
        unawaited(load());
      }
    }
  }

  Future<void> command(String action) async {
    if (busy || item == null) return;
    final current = item!,
        session = ref.read(sessionProvider),
        ticket = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(workRepositoryProvider);
      final signature = jsonEncode([
        action,
        current.id,
        current.version,
        current.planVersion,
        current.json['planHash'],
        current.json['confirmationId'],
      ]);
      if (signature != commandSignature) {
        commandSignature = signature;
        commandKey = AiWorkRepository.key();
      }
      final next = action == 'confirm'
          ? await repo.confirm(current, commandKey)
          : await repo.command(current, action, commandKey);
      if (mounted &&
          ticket == generation &&
          ref.read(sessionProvider).id == session.id &&
          ref.read(sessionProvider).token == session.token) {
        setState(() {
          if (item == null || next.version >= item!.version) item = next;
          commandKey = AiWorkRepository.key();
        });
      }
      ref.invalidate(workListProvider);
    } catch (e) {
      if (mounted &&
          ticket == generation &&
          ref.read(sessionProvider).id == session.id &&
          ref.read(sessionProvider).token == session.token) {
        failed(e);
        if (e is ApiFailure && e.kind == FailureKind.conflict) {
          pendingLoad = true;
        }
      }
    } finally {
      if (mounted && ticket == generation) {
        setState(() => busy = false);
        if (pendingLoad) {
          pendingLoad = false;
          unawaited(load());
        }
      }
    }
  }

  Future<void> clear() async {
    if (busy || item == null) return;
    final dialogTicket = generation;
    final approved = await showDialog<bool>(
      context: context,
      animationStyle: WorkMotion.dialog(context),
      builder: (context) => AlertDialog(
        title: const Text('清除私人记录？'),
        content: const Text('这件事的对话和私人材料将被清除，已经办理的任务与交付会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除私人记录'),
          ),
        ],
      ),
    );
    if (approved != true || !current(dialogTicket) || item == null || busy) {
      return;
    }
    final session = ref.read(sessionProvider), ticket = ++generation;
    setState(() => busy = true);
    try {
      final signature = 'delete:${item!.id}:${item!.version}';
      if (signature != commandSignature) {
        commandSignature = signature;
        commandKey = AiWorkRepository.key();
      }
      await ref.read(workRepositoryProvider).delete(item!, commandKey);
      if (!mounted ||
          ticket != generation ||
          ref.read(sessionProvider).id != session.id ||
          ref.read(sessionProvider).token != session.token) {
        return;
      }
      ref.invalidate(workListProvider);
      context.pop();
    } catch (e) {
      if (mounted && ticket == generation) failed(e);
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    ref.listen(workEventsProvider(widget.id), (_, event) {
      if (accountChanged) return;
      if (!event.hasError &&
          event.hasValue &&
          foreground &&
          !accessLost &&
          !accountChanged) {
        unawaited(load());
      }
      if (event.error is ApiFailure &&
          [
            FailureKind.unauthorized,
            FailureKind.forbidden,
            FailureKind.notFound,
          ].contains((event.error as ApiFailure).kind)) {
        setState(() {
          generation++;
          item = null;
          error = event.error;
          accessLost = true;
          busy = false;
          selectedOwnerId = null;
          selectedTask = null;
          input.clear();
        });
      }
    });
    ref.listen(sessionProvider, (before, after) {
      if (before?.token != after.token ||
          before?.id != after.id ||
          !after.canReadBusiness) {
        setState(() {
          generation++;
          item = null;
          error = const ApiFailure(
            FailureKind.forbidden,
            '账号已切换，请重新打开事项',
            code: 'WORK_ACCOUNT_CHANGED',
          );
          accountChanged = true;
          busy = false;
          selectedOwnerId = null;
          selectedTask = null;
          input.clear();
          focus.unfocus();
        });
        timer?.cancel();
      }
    });
    final value = item;
    return WorkMotionScope(
      child: Scaffold(
        backgroundColor: SunnyPalette.paper,
        appBar: AppBar(
          title: const Text('办理详情'),
          actions: [
            if (value != null)
              IconButton(
                tooltip: '清除私人记录',
                onPressed: busy ? null : clear,
                icon: const Icon(Icons.delete_outline),
              ),
            if (value != null &&
                ![
                  'CANCELLED',
                  'CANCEL_REQUESTED',
                  'SUCCEEDED',
                ].contains(value.state))
              TextButton(
                onPressed: busy ? null : () => command('cancel'),
                child: const Text('停止'),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: load,
                  child: value == null
                      ? ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            const SizedBox(height: 100),
                            if (error != null)
                              Text(
                                workError(error!),
                                textAlign: TextAlign.center,
                              )
                            else
                              const Center(child: CircularProgressIndicator()),
                            if (error != null)
                              TextButton(
                                onPressed: accountChanged
                                    ? () => context.go('/ai')
                                    : load,
                                child: Text(accountChanged ? '返回事项列表' : '重试'),
                              ),
                          ],
                        )
                      : ListView(
                          key: PageStorageKey(
                            'work-detail-${widget.id}:${session.id}:${session.token}',
                          ),
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final message in value.messages)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: PaperSurface(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${workMap(message['body'])['text'] ?? ''}',
                                      ),
                                      if ((workMap(
                                                    message['body'],
                                                  )['attachmentIds']
                                                  as List? ??
                                              [])
                                          .isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            '已添加 ${(workMap(message['body'])['attachmentIds'] as List).length} 份材料',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            AnimatedSize(
                              duration: WorkMotion.duration(context),
                              alignment: Alignment.topCenter,
                              child: PaperSurface(
                                key: const ValueKey('work-result'),
                                color: SunnyPalette.purple,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Semantics(
                                      container: true,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: OutlinedButton.icon(
                                              icon: const Icon(
                                                Icons.task_outlined,
                                              ),
                                              label: Text(
                                                selectedTask == null
                                                    ? '选择任务'
                                                    : '${selectedTask!['title']}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              onPressed: () async {
                                                if (busy) return;
                                                final ticket = generation;
                                                final picked =
                                                    await showDialog<
                                                      Map<String, dynamic>
                                                    >(
                                                      context: context,
                                                      animationStyle:
                                                          WorkMotion.dialog(
                                                            context,
                                                          ),
                                                      builder: (_) =>
                                                          const WorkTargetPicker(
                                                            'CHECK_DELIVERY',
                                                          ),
                                                    );
                                                if (picked == null ||
                                                    !current(ticket)) {
                                                  return;
                                                }
                                                try {
                                                  final task = await ref
                                                      .read(
                                                        workRepositoryProvider,
                                                      )
                                                      .request(
                                                        'GET',
                                                        '/tasks/${picked['id']}',
                                                      );
                                                  if (!current(ticket)) return;
                                                  setState(
                                                    () => selectedTask = task,
                                                  );
                                                  input.text =
                                                      '${input.text} 已选择任务「${picked['label']}」';
                                                  focus.requestFocus();
                                                } catch (e) {
                                                  if (current(ticket)) {
                                                    failed(e);
                                                  }
                                                }
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              if (value.processing)
                                                const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              else
                                                Icon(
                                                  value.state == 'SUCCEEDED'
                                                      ? Icons
                                                            .check_circle_outline_rounded
                                                      : Icons
                                                            .auto_awesome_rounded,
                                                ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Semantics(
                                                  liveRegion: true,
                                                  child: Text(
                                                    value.label,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.titleMedium,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '${value.result['summary'] ?? ''}',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    if ('${value.plan['answer'] ?? ''}'
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: SelectableText(
                                          '${value.plan['answer']}',
                                        ),
                                      ),
                                    for (final question in value.questions)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(
                                          question,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    if (value.state == 'WAITING_INPUT')
                                      Wrap(
                                        spacing: 12,
                                        children: [
                                          if (workMaps(
                                            value.plan['people'],
                                          ).isNotEmpty)
                                            OutlinedButton.icon(
                                              icon: const Icon(
                                                Icons.person_outline,
                                              ),
                                              label: const Text('选择负责人'),
                                              onPressed: () async {
                                                if (busy) return;
                                                final ticket = generation;
                                                final person = await showModalBottomSheet<Map<String, dynamic>>(
                                                  context: context,
                                                  isScrollControlled: true,
                                                  builder: (context) => Consumer(
                                                    builder: (context, ref, _) {
                                                      ref.watch(
                                                        sessionProvider,
                                                      );
                                                      if (!current(ticket)) {
                                                        return const SafeArea(
                                                          child: Padding(
                                                            padding:
                                                                EdgeInsets.all(
                                                                  24,
                                                                ),
                                                            child: Text(
                                                              '这件事已无法查看，请返回事项列表',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                      return SafeArea(
                                                        child: SizedBox(
                                                          height:
                                                              MediaQuery.sizeOf(
                                                                context,
                                                              ).height *
                                                              .6,
                                                          child: ListView(
                                                            children: [
                                                              const ListTile(
                                                                title: Text(
                                                                  '交给谁来办',
                                                                ),
                                                              ),
                                                              for (final person
                                                                  in workMaps(
                                                                    value
                                                                        .plan['people'],
                                                                  ))
                                                                ListTile(
                                                                  title: Text(
                                                                    '${person['name']}',
                                                                  ),
                                                                  subtitle: Text(
                                                                    '${person['team_name'] ?? person['department_name'] ?? ''}',
                                                                  ),
                                                                  onTap: () =>
                                                                      Navigator.pop(
                                                                        context,
                                                                        person,
                                                                      ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                );
                                                if (person == null ||
                                                    !current(ticket)) {
                                                  return;
                                                }
                                                selectedOwnerId =
                                                    '${person['id']}';
                                                input.text =
                                                    '${input.text} 负责人：${person['name']}';
                                                focus.requestFocus();
                                              },
                                            ),
                                          OutlinedButton.icon(
                                            icon: const Icon(
                                              Icons.calendar_month_outlined,
                                            ),
                                            label: const Text('选择截止时间'),
                                            onPressed: () async {
                                              if (busy) return;
                                              final ticket = generation;
                                              final now = DateTime.now();
                                              final day = await showDatePicker(
                                                context: context,
                                                initialDate: now.add(
                                                  const Duration(days: 1),
                                                ),
                                                firstDate: now,
                                                lastDate: now.add(
                                                  const Duration(days: 3650),
                                                ),
                                              );
                                              if (day == null ||
                                                  !context.mounted ||
                                                  !current(ticket)) {
                                                return;
                                              }
                                              final time = await showTimePicker(
                                                context: context,
                                                initialTime: const TimeOfDay(
                                                  hour: 18,
                                                  minute: 0,
                                                ),
                                              );
                                              if (time == null ||
                                                  !current(ticket)) {
                                                return;
                                              }
                                              input.text =
                                                  '${input.text} 截止时间：${day.year}年${day.month}月${day.day}日${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                                              focus.requestFocus();
                                            },
                                          ),
                                        ],
                                      ),
                                    if (value.state ==
                                        'WAITING_CONFIRMATION') ...[
                                      for (final action in value.actions)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 12,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${action['label'] ?? ''}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (workMap(
                                                    action['payload'],
                                                  )['deadline'] !=
                                                  null)
                                                Text(
                                                  '截止 ${workDate(workMap(action['payload'])['deadline'])}',
                                                ),
                                              if (workMaps(
                                                action['similarTasks'],
                                              ).isNotEmpty) ...[
                                                const SizedBox(height: 12),
                                                const Text('已有相似任务，要继续处理原任务吗？'),
                                                for (final task in workMaps(
                                                  action['similarTasks'],
                                                ))
                                                  TextButton.icon(
                                                    onPressed: () => context.push(
                                                      '/item/tasks/${task['id']}',
                                                    ),
                                                    icon: const Icon(
                                                      Icons.open_in_new_rounded,
                                                    ),
                                                    label: Text(
                                                      '${task['title']}',
                                                    ),
                                                  ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 16),
                                      FilledButton(
                                        onPressed:
                                            busy ||
                                                value.json['planValid'] == false
                                            ? null
                                            : () => command('confirm'),
                                        child: Text(
                                          value.actions.every(
                                                (a) =>
                                                    a['type'] == 'CREATE_TASK',
                                              )
                                              ? value.actions.any(
                                                      (a) => workMaps(
                                                        a['similarTasks'],
                                                      ).isNotEmpty,
                                                    )
                                                    ? '仍然创建任务'
                                                    : '创建任务'
                                              : value.actions.every(
                                                  (a) =>
                                                      a['type'] ==
                                                      'SUBMIT_DELIVERY',
                                                )
                                              ? '提交反馈'
                                              : '办理以上事项',
                                        ),
                                      ),
                                    ],
                                    if ([
                                          'FAILED',
                                          'PARTIAL',
                                        ].contains(value.state) ||
                                        value.state == 'WAITING_CONFIRMATION' &&
                                            value.json['planValid'] == false)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: OutlinedButton(
                                          onPressed: busy
                                              ? null
                                              : () => command('retry'),
                                          child: Text(
                                            value.json['planValid'] == false
                                                ? '重新核对'
                                                : '继续处理',
                                          ),
                                        ),
                                      ),
                                    if (workMaps(
                                      value.plan['sources'],
                                    ).isNotEmpty)
                                      ExpansionTile(
                                        tilePadding: EdgeInsets.zero,
                                        title: const Text('查看依据'),
                                        children: [
                                          for (final source in workMaps(
                                            value.plan['sources'],
                                          ))
                                            ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text('${source['title']}'),
                                              subtitle: Text(
                                                '第 ${source['version']} 版 · ${workMaps(source['excerpts']).map((part) => part['locator']).join('、')}',
                                              ),
                                              onTap: () => context.push(
                                                '/ai/procedures/${source['id']}',
                                              ),
                                            ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            for (final receipt in value.receipts)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: _ReceiptCard(
                                  workMap(receipt['result']),
                                  key: ValueKey(receipt['step_key']),
                                ),
                              ),
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Text(workError(error!)),
                              ),
                          ],
                        ),
                ),
              ),
              if (value != null &&
                  !['CANCELLED', 'CANCEL_REQUESTED'].contains(value.state))
                WorkComposer(
                  key: ValueKey(
                    '${widget.id}:${session.id}:${session.token}:${session.canReadBusiness}',
                  ),
                  controller: input,
                  focus: focus,
                  requestContext: jsonEncode([
                    value.id,
                    value.version,
                    selectedOwnerId,
                    selectedTask?['id'],
                    selectedTask?['version'],
                  ]),
                  onSend: (text, files, key) async {
                    if (busy || accessLost || accountChanged) {
                      throw const ApiFailure(FailureKind.conflict, '请稍后重试');
                    }
                    final ticket = ++generation;
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final next = await ref
                          .read(workRepositoryProvider)
                          .message(
                            value,
                            text,
                            files,
                            key,
                            ownerId: selectedOwnerId,
                            taskId: selectedTask?['id'] as String?,
                            taskVersion: selectedTask?['version'] as int?,
                          );
                      if (mounted &&
                          ticket == generation &&
                          !accessLost &&
                          !accountChanged &&
                          ref.read(sessionProvider).id == session.id &&
                          ref.read(sessionProvider).token == session.token) {
                        setState(() {
                          if (item == null || next.version >= item!.version) {
                            item = next;
                          }
                          selectedOwnerId = null;
                          selectedTask = null;
                        });
                      }
                      ref.invalidate(workListProvider);
                    } catch (e) {
                      if (current(ticket)) {
                        failed(e);
                        if (e is ApiFailure && e.kind == FailureKind.conflict) {
                          pendingLoad = true;
                        }
                      }
                      rethrow;
                    } finally {
                      if (mounted && ticket == generation) {
                        setState(() => busy = false);
                        if (pendingLoad) {
                          pendingLoad = false;
                          unawaited(load());
                        }
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatefulWidget {
  const _ReceiptCard(this.result, {super.key});
  final Map<String, dynamic> result;
  @override
  State<_ReceiptCard> createState() => _ReceiptCardState();
}

class _ReceiptCardState extends State<_ReceiptCard> {
  bool arrived = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => arrived = true);
    });
  }

  Map<String, dynamic> get result => widget.result;
  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: arrived ? 1 : 0,
    duration: MediaQuery.disableAnimationsOf(context) || !TickerMode.of(context)
        ? Duration.zero
        : WorkMotion.success,
    child: PaperSurface(
      color: SunnyPalette.mint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${result['summary'] ?? '办理记录'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final finding in workMaps(workMap(result['report'])['findings']))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    finding['state'] == 'PASS'
                        ? Icons.check_rounded
                        : Icons.info_outline_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${finding['title']}\n${finding['message']}${'${finding['locator'] ?? ''}'.isEmpty ? '' : ' · ${finding['locator']}'}',
                    ),
                  ),
                ],
              ),
            ),
          if (result['taskId'] is String)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton(
                onPressed: () => context.push(
                  '/item/tasks/${Uri.encodeComponent(result['taskId'] as String)}',
                ),
                child: const Text('查看任务'),
              ),
            ),
          if (result['reviewId'] is String)
            TextButton(
              onPressed: () => context.push(
                '/me/reviews/${Uri.encodeComponent(result['reviewId'] as String)}',
              ),
              child: const Text('查看复核'),
            ),
        ],
      ),
    ),
  );
}
