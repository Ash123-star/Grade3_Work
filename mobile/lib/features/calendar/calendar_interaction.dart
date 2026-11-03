import '../../core/state/live_notifications.dart';
import '../../core/errors/api_failure.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/state/providers.dart';
import '../../core/state/local_state.dart';
import '../../data/local/calendar_command_store.dart';
import '../../data/models/models.dart';
import '../../shared/premium_pickers.dart';
import '../../shared/widgets.dart';
import 'calendar_drag_controller.dart';
import 'calendar_schedule.dart';
import 'calendar_submission.dart';

class CalendarInteraction extends InheritedWidget {
  const CalendarInteraction({
    super.key,
    required this.state,
    required super.child,
  });
  final CalendarInteractionSurfaceState state;
  static CalendarInteractionSurfaceState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CalendarInteraction>()?.state;
  @override
  bool updateShouldNotify(CalendarInteraction oldWidget) => true;
}

class CalendarInteractionSurface extends ConsumerStatefulWidget {
  const CalendarInteractionSurface({
    super.key,
    required this.scroll,
    required this.readOnly,
    required this.builder,
  });
  final ScrollController scroll;
  final bool readOnly;
  final Widget Function(BuildContext, bool) builder;
  @override
  ConsumerState<CalendarInteractionSurface> createState() =>
      CalendarInteractionSurfaceState();
}

class CalendarInteractionSurfaceState
    extends ConsumerState<CalendarInteractionSurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final viewport = GlobalKey();
  late final CalendarDragController drag;
  late int epoch;
  OverlayEntry? overlay;
  CalendarMoveCommand? pending;
  bool foreground = true,
      busy = false,
      restoring = true,
      confirming = false,
      multiTouch = false;
  String? message;
  int operation = 0, pointers = 0;
  Size? _size;
  double? _scale;
  bool _renderedDragging = false;
  bool get current =>
      mounted &&
      ref.read(sessionProvider).canReadBusiness &&
      ref.read(sessionEpochProvider) == epoch;
  bool get writable =>
      current &&
      !widget.readOnly &&
      foreground &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    epoch = ref.read(sessionEpochProvider);
    drag = CalendarDragController(
      vsync: this,
      scroll: widget.scroll,
      viewport: viewport,
      allowed: () => writable && !busy && !confirming,
    )..addListener(_previewChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restore());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context),
        scale = MediaQuery.textScalerOf(context).scale(1);
    if (_size != null && (_size != size || _scale != scale)) drag.cancel();
    _size = size;
    _scale = scale;
  }

  @override
  void didChangeMetrics() {
    drag.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      drag.cancel();
      return;
    }
    if (current) {
      refreshBusiness(ref);
      unawaited(_restore(queryKnown: true));
    }
  }

  Future<void> _restore({bool queryKnown = false}) async {
    if (widget.readOnly) {
      if (mounted) setState(() => restoring = false);
      return;
    }
    final generation = operation, session = ref.read(sessionProvider);
    try {
      final command = await ref
          .read(calendarCommandStoreProvider)
          .read(session);
      if (!current || generation != operation) return;
      setState(() {
        pending = command;
        restoring = false;
      });
      if (queryKnown && command?.reviewId != null && !busy) {
        await confirmPending();
      }
    } catch (e) {
      if (current && generation == operation) {
        setState(() {
          message = '$e';
          restoring = false;
        });
      }
    }
  }

  void _previewChanged() {
    if (!mounted) return;
    if (drag.active) {
      overlay ??= OverlayEntry(builder: (_) => _overlay());
      if (!overlay!.mounted) Overlay.of(context).insert(overlay!);
      overlay!.markNeedsBuild();
    } else {
      overlay?.remove();
      overlay?.dispose();
      overlay = null;
    }
    // Only the start/end transition changes paging physics and back handling.
    // Pointer/target updates already notify the overlay and individual day cells;
    // rebuilding PageView and every month on each scroll frame adds avoidable work.
    if (_renderedDragging != drag.active) {
      setState(() => _renderedDragging = drag.active);
    }
  }

  Widget _overlay() {
    final area = drag.bounds, value = drag.intent;
    if (area == null || value == null) return const SizedBox.shrink();
    final width = (area.width - 24).clamp(120.0, 320.0);
    final left = (drag.pointer.dx - width / 2).clamp(
      area.left + 4,
      area.right - width - 4,
    );
    return Positioned(
      left: left,
      top: (drag.pointer.dy - 120).clamp(area.top, area.bottom - 100),
      width: width,
      child: IgnorePointer(
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.record.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  drag.target == null
                      ? '移到已加载日期内'
                      : businessDateText(drag.target!.day),
                ),
                Text(drag.preview?.description ?? '此落点超出排期范围'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void begin(Record record, Offset point, CalendarConstraints constraints) {
    if (restoring ||
        busy ||
        pending != null ||
        confirming ||
        multiTouch ||
        !writable) {
      if (pending != null) notice(context, '请先确认上一条改期申请的结果');
      return;
    }
    if (drag.begin(record, point, constraints)) {
      unawaited(HapticFeedback.selectionClick());
    } else {
      setState(() => message = '当前任务排期无效或日期尚未加载，请刷新后重试');
    }
  }

  void drop() {
    final intent = drag.intent, target = drag.target, preview = drag.preview;
    drag.cancel();
    if (intent == null || target == null || preview == null || !writable) {
      return;
    }
    final delta = businessDayDelta(intent.anchor, target.day);
    if (delta != 0) unawaited(move(intent.record, delta, intent.constraints));
  }

  Future<void> accessible(
    Record record,
    CalendarConstraints constraints,
  ) async {
    if (!writable || busy || restoring || confirming || pending != null) return;
    final generation = operation;
    try {
      final schedule = CalendarSchedule.fromRecord(record),
          seed = schedule.firstDay;
      if (!constraints.contains(seed)) {
        throw const FormatException('当前排期超出选择范围，请刷新后查看');
      }
      final target = await showPremiumDatePicker(
        context,
        initial: seed,
        firstDate: constraints.min,
        lastDate: constraints.max,
        title: '移动到日期（上海）',
      );
      if (!writable || generation != operation || target == null) return;
      final delta = businessDayDelta(seed, target);
      if (delta != 0) await move(record, delta, constraints);
    } catch (e) {
      if (current) setState(() => message = '$e');
    }
  }

  Future<void> move(
    Record record,
    int days,
    CalendarConstraints constraints,
  ) async {
    if (!writable || busy || confirming || pending != null) return;
    final generation = ++operation;
    final repository = ref.read(repositoryProvider);
    bool valid() => writable && operation == generation;
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    setState(() => confirming = true);
    try {
      final source = await repository.detail('tasks', record.id);
      if (!mounted || !valid()) return;
      if (source.version != record.version ||
          source.fields['capabilities'] is! Map ||
          source.fields['capabilities']['reschedule'] != true) {
        throw const FormatException('任务版本或权限已变化，请刷新后重新移动');
      }
      final before = CalendarSchedule.fromRecord(source),
          after = CalendarSchedule.fromRecord(source).move(days, constraints);
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('确认移动排期'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('原排期：${before.description}'),
                  const SizedBox(height: 12),
                  Text('新排期：${after.description}'),
                  const SizedBox(height: 12),
                  const Text('提交后等待独立审核，审核通过前任务留在原日期。'),
                  TextFormField(
                    controller: reason,
                    autofocus: true,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '移动原因（1–1000 字）',
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      return text.isEmpty || text.runes.length > 1000
                          ? '请填写 1–1000 字原因'
                          : null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(dialog, true);
              },
              child: const Text('提交审核'),
            ),
          ],
        ),
      );
      if (yes != true || !valid()) return;
      // Confirm the authoritative source again after an arbitrarily long dialog.
      final latest = await repository.detail('tasks', record.id);
      if (!valid()) return;
      if (latest.version != source.version ||
          latest.fields['capabilities'] is! Map ||
          latest.fields['capabilities']['reschedule'] != true) {
        throw const FormatException('任务已更新，原移动已取消，请刷新');
      }
      final command = CalendarMoveCommand(
        taskId: record.id,
        version: source.version,
        days: days,
        reason: reason.text.trim(),
        key: newCalendarCommandKey(),
        revision: constraints.revision,
      );
      // The in-memory intent is retained if secure persistence fails; no request is sent.
      setState(() => pending = command);
      await confirmPending();
    } catch (e) {
      if (valid()) {
        setState(() => message = '$e');
        refreshBusiness(ref);
      }
    } finally {
      reason.dispose();
      if (mounted && operation == generation) {
        setState(() => confirming = false);
      }
    }
  }

  Future<void> confirmPending() async {
    final command = pending;
    if (command == null || busy || !writable) return;
    final generation = operation, session = ref.read(sessionProvider);
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result =
          await CalendarSubmission(
            ref.read(repositoryProvider),
            ref.read(calendarCommandStoreProvider),
            session,
          ).confirm(
            command,
            sameSession: () => current && operation == generation,
            foreground: () =>
                foreground && ModalRoute.of(context)?.isCurrent != false,
          );
      if (!current || operation != generation) return;
      if (result == null) {
        setState(() => message = '提交结果待确认，请使用原命令继续确认');
        return;
      }
      final status = '${result.fields['status']}';
      pending = command.reviewed(result.id);
      if (status == 'APPROVED' || status == 'REJECTED') {
        await ref.read(calendarCommandStoreProvider).clear(session);
        if (!current || operation != generation) return;
        pending = null;
        refreshBusiness(ref);
      }
      setState(
        () => message = switch (status) {
          'APPROVED' => '移动已审核通过，正在刷新排期',
          'REJECTED' => '申请已驳回，原排期保留；可打开申请查看原因',
          _ => '移动申请待审，任务保留原排期',
        },
      );
    } catch (e) {
      if (current && operation == generation) {
        CalendarMoveCommand? restored;
        try {
          restored = await ref.read(calendarCommandStoreProvider).read(session);
        } catch (_) {
          // Retain the original key if secure storage itself is unavailable.
          restored = command;
        }
        if (!current || operation != generation) return;
        final rejected =
            e is ApiFailure &&
            e.statusCode != 429 &&
            const [
              FailureKind.validation,
              FailureKind.unauthorized,
              FailureKind.forbidden,
              FailureKind.notFound,
              FailureKind.conflict,
            ].contains(e.kind);
        setState(() {
          pending = rejected ? null : restored ?? command;
          message = '$e';
        });
        refreshBusiness(ref);
      }
    } finally {
      if (mounted && operation == generation) setState(() => busy = false);
    }
  }

  void create(DateTime day, CalendarConstraints constraints) {
    final session = ref.read(sessionProvider);
    if (!writable ||
        multiTouch ||
        drag.active ||
        busy ||
        confirming ||
        !session.manager ||
        !session.dispatch ||
        !constraints.contains(day)) {
      return;
    }
    context.push(
      Uri(
        path: '/form/dispatch',
        queryParameters: {
          'initialBusinessDate': businessDateText(day),
          'calendarMinDate': businessDateText(constraints.min),
          'calendarMaxDate': businessDateText(constraints.max),
          'calendarRevision': constraints.revision,
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(sessionEpochProvider, (_, next) {
      epoch = next;
      operation++;
      drag.cancel();
      pending = null;
      busy = false;
      message = null;
      restoring = true;
      unawaited(_restore());
    });
    ref.listen(liveNotificationsProvider.select((state) => state.sequence), (
      previous,
      next,
    ) {
      if (previous != next && current) {
        drag.cancel();
        refreshBusiness(ref);
        unawaited(_restore(queryKnown: true));
      }
    });
    return CalendarInteraction(
      state: this,
      child: PopScope(
        canPop: !drag.active,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) drag.cancel();
        },
        child: Listener(
          onPointerDown: (_) {
            pointers++;
            if (pointers > 1) {
              multiTouch = true;
              drag.cancel();
            }
          },
          onPointerUp: (_) {
            pointers = (pointers - 1).clamp(0, 10);
            if (pointers == 0) multiTouch = false;
          },
          onPointerCancel: (_) {
            pointers = (pointers - 1).clamp(0, 10);
            if (pointers == 0) multiTouch = false;
            drag.cancel();
          },
          child: Column(
            children: [
              if (message != null || pending != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        message ??
                            (pending!.reviewId == null ? '提交结果待确认' : '有待审移动申请'),
                      ),
                      if (pending != null)
                        TextButton(
                          onPressed: busy ? null : confirmPending,
                          child: Text(busy ? '正在确认' : '确认结果'),
                        ),
                      if (pending?.reviewId != null)
                        TextButton(
                          onPressed: () =>
                              openItem(context, 'reviews', pending!.reviewId!),
                          child: const Text('查看申请'),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: SizedBox(
                  key: viewport,
                  child: widget.builder(context, drag.active),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    operation++;
    WidgetsBinding.instance.removeObserver(this);
    drag.removeListener(_previewChanged);
    drag.dispose();
    overlay?.remove();
    overlay?.dispose();
    super.dispose();
  }
}

/// Loaded page bounds let edge scrolling cross weekday headers and blank cells.
/// They are never drop targets or quick-create surfaces.
class CalendarLoadedMonth extends StatefulWidget {
  const CalendarLoadedMonth({
    super.key,
    required this.month,
    required this.constraints,
    required this.child,
  });
  final DateTime month;
  final CalendarConstraints? constraints;
  final Widget child;
  @override
  State<CalendarLoadedMonth> createState() => _CalendarLoadedMonthState();
}

class _CalendarLoadedMonthState extends State<CalendarLoadedMonth> {
  final geometry = GlobalKey();
  CalendarInteractionSurfaceState? interaction;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    interaction = CalendarInteraction.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final constraints = widget.constraints;
    if (constraints != null) {
      interaction?.drag.loadedMonths[this] = CalendarDayGeometry(
        geometry,
        widget.month,
        constraints,
      );
    } else {
      interaction?.drag.loadedMonths.remove(this);
    }
    return SizedBox(key: geometry, child: widget.child);
  }

  @override
  void dispose() {
    interaction?.drag.loadedMonths.remove(this);
    super.dispose();
  }
}

class CalendarDayTarget extends StatefulWidget {
  const CalendarDayTarget({
    super.key,
    required this.day,
    required this.constraints,
    required this.child,
  });
  final DateTime day;
  final CalendarConstraints? constraints;
  final Widget child;
  @override
  State<CalendarDayTarget> createState() => _CalendarDayTargetState();
}

class _CalendarDayTargetState extends State<CalendarDayTarget> {
  final geometry = GlobalKey();
  CalendarInteractionSurfaceState? interaction;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    interaction = CalendarInteraction.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = interaction, constraints = widget.constraints;
    if (state != null && constraints != null) {
      state.drag.targets[this] = CalendarDayGeometry(
        geometry,
        widget.day,
        constraints,
      );
    } else {
      state?.drag.targets.remove(this);
    }
    return SizedBox(
      key: geometry,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: state == null || constraints == null
            ? null
            : () => state.create(widget.day, constraints),
        child: AnimatedBuilder(
          animation: state?.drag ?? const AlwaysStoppedAnimation(0),
          builder: (context, child) => DecoratedBox(
            decoration: BoxDecoration(
              border:
                  state?.drag.active == true &&
                      state?.drag.target?.day == widget.day
                  ? Border.all(
                      color: state!.drag.preview == null
                          ? Colors.red
                          : Colors.blue,
                      width: 2,
                    )
                  : null,
            ),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    interaction?.drag.targets.remove(this);
    super.dispose();
  }
}

class CalendarTaskHandle extends StatelessWidget {
  const CalendarTaskHandle({
    super.key,
    required this.record,
    required this.constraints,
    required this.child,
    required this.onTap,
  });
  final Record record;
  final CalendarConstraints? constraints;
  final Widget child;
  final ValueChanged<Offset> onTap;
  @override
  Widget build(BuildContext context) {
    final state = CalendarInteraction.of(context), bounds = constraints;
    final enabled =
        state != null &&
        !state.widget.readOnly &&
        bounds != null &&
        record.fields['capabilities'] is Map &&
        record.fields['capabilities']['reschedule'] == true;
    return Semantics(
      label: record.title,
      button: true,
      customSemanticsActions: enabled
          ? {
              const CustomSemanticsAction(label: '移动到日期'): () =>
                  state.accessible(record, bounds),
            }
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => onTap(details.globalPosition),
        onLongPressStart: enabled
            ? (details) => state.begin(record, details.globalPosition, bounds)
            : null,
        onLongPressMoveUpdate: enabled
            ? (details) => state.drag.update(details.globalPosition)
            : null,
        onLongPressEnd: enabled ? (_) => state.drop() : null,
        onLongPressCancel: () => state?.drag.cancel(),
        child: child,
      ),
    );
  }
}
