import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/data/local/draft_store.dart';
import 'package:pandora_mobile/data/models/log_edit_window.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

Future<bool?> showDiaryComposer(
  BuildContext context,
  WidgetRef ref, {
  DateTime? date,
  String? recordId,
  int? version,
}) => showTuantuanBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  showDragHandle: false,
  useSafeArea: true,
  isDismissible: true,
  enableDrag: true,
  barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .7),
  builder: (_) =>
      DiaryComposerSheet(date: date, recordId: recordId, version: version),
);

/// Handles legacy /form/log-edit links by opening the composer over the current page.
class DiaryComposerRoutePage extends ConsumerStatefulWidget {
  const DiaryComposerRoutePage({super.key, this.id, this.version});
  final String? id;
  final int? version;

  @override
  ConsumerState<DiaryComposerRoutePage> createState() =>
      _DiaryComposerRoutePageState();
}

class _DiaryComposerRoutePageState
    extends ConsumerState<DiaryComposerRoutePage> {
  bool _opening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opening) return;
    _opening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDiaryComposer(
        context,
        ref,
        date: ref.read(logDateProvider),
        recordId: widget.id,
        version: widget.version,
      );
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/logs');
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    body: const SizedBox.expand(),
  );
}

class DiaryComposerSheet extends ConsumerStatefulWidget {
  const DiaryComposerSheet({super.key, this.date, this.recordId, this.version});
  final DateTime? date;
  final String? recordId;
  final int? version;

  @override
  ConsumerState<DiaryComposerSheet> createState() => _DiaryComposerSheetState();
}

class _DiaryComposerSheetState extends ConsumerState<DiaryComposerSheet>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final String _accountId;
  late final String? _sessionToken;
  late final DateTime _date;
  late final DraftLocation _location;
  late final DraftStore _draftStore;
  Timer? _saveTimer;
  Timer? _editWindowTimer;
  Future<void> _saveQueue = Future.value();
  String? _recordId;
  int? _version;
  int _revision = 0;
  bool _loading = true;
  bool _restoreFailed = false;
  bool _saving = false;
  bool _submitting = false;
  bool _submitted = false;
  bool _hasSubmittedBefore = false;
  bool _readOnly = false;
  bool _closing = false;
  bool _allowPop = false;
  bool _keyboardCollapsedForSpace = false;
  late Future<void> _restoreFuture;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final session = ref.read(sessionProvider);
    _accountId = session.id;
    _sessionToken = session.token;
    _draftStore = ref.read(draftStoreProvider);
    final selected = widget.date ?? ref.read(logDateProvider);
    final resolved = selected ?? DateTime.now();
    _date = DateTime(resolved.year, resolved.month, resolved.day);
    _location = DraftLocation.diary(_accountId, _date);
    _recordId = widget.recordId;
    _version = widget.version;
    _restoreFuture = _restore();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = View.of(context);
    final scale = view.devicePixelRatio;
    final screenHeight = view.physicalSize.height / scale;
    final keyboardHeight = view.viewInsets.bottom / scale;
    if (keyboardHeight == 0) {
      if (_keyboardCollapsedForSpace) {
        _keyboardCollapsedForSpace = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
      return;
    }
    if (screenHeight > 0 && keyboardHeight + 112 > screenHeight * 2 / 3) {
      if (!_keyboardCollapsedForSpace) {
        _keyboardCollapsedForSpace = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.unfocus();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveDraft());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _editWindowTimer?.cancel();
    if (!_submitted && _controller.text.isNotEmpty) {
      unawaited(
        _enqueueSave(_controller.text, _revision).catchError((Object _) {}),
      );
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isCurrentAccount {
    final session = ref.read(sessionProvider);
    return session.id == _accountId && session.token == _sessionToken && session.canReadBusiness;
  }

  Future<void> _restore() async {
    try {
      final local = await ref.read(draftStoreProvider).read(_location);
      if (!mounted || !_isCurrentAccount) return;
      if (local != null) {
        _controller.text = local.fields['今日工作'] ?? '';
        _recordId = local.serverId ?? _recordId;
        _version = local.serverVersion ?? _version;
      }
      if (_recordId != null) {
        final record = await ref
            .read(repositoryProvider)
            .detail('logs', _recordId!);
        if (!mounted || !_isCurrentAccount) return;
        if (record.ownerId != _accountId ||
            record.fields['businessDate'] != _dayKey) {
          throw const ApiFailure(FailureKind.forbidden, '日志不属于当前账号或日期');
        }
        final localWork = local?.fields['今日工作'];
        final serverWork = '${record.fields['今日工作'] ?? ''}';
        if (_version != null &&
            record.version != _version &&
            localWork != null &&
            localWork != serverWork) {
          throw const ApiFailure(
            FailureKind.conflict,
            '日志版本已变化且正文已更新，请从日志页重新打开',
          );
        }
        _hasSubmittedBefore = isSubmittedDiary(record);
        _readOnly =
            _hasSubmittedBefore &&
            !LogEditWindow(record).canEditAt(DateTime.now());
        final until = LogEditWindow(record).until;
        if (_hasSubmittedBefore && !_readOnly && until != null) {
          _editWindowTimer = Timer(until.difference(DateTime.now()), () {
            if (mounted) setState(() => _readOnly = true);
          });
        }
        if (local == null) {
          _controller.text = '${record.fields['今日工作'] ?? ''}';
        }
        if (_readOnly) _controller.text = '${record.fields['今日工作'] ?? ''}';
        _version = record.version;
      }
    } catch (error) {
      if (mounted && _isCurrentAccount) {
        setState(() {
          _restoreFailed = true;
          _error = '草稿读取失败：$error';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _dayKey =>
      '${_date.year.toString().padLeft(4, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.day.toString().padLeft(2, '0')}';

  void _changed(String _) {
    if (_loading || _closing || _submitted || _readOnly) return;
    _revision++;
    _saveTimer?.cancel();
    setState(() {
      _saving = true;
      _error = null;
    });
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveDraft());
    });
  }

  Future<void> _enqueueSave(String text, int revision) {
    final operation = _saveQueue.catchError((Object _) {}).then((_) async {
      if (text.trim().isEmpty) {
        await _draftStore.remove(_location);
      } else {
        await _draftStore.write(
          _location,
          LocalDraft(
            fields: {'今日工作': text},
            savedAt: DateTime.now(),
            serverId: _recordId,
            serverVersion: _version,
          ),
        );
      }
      if (mounted && revision == _revision && _isCurrentAccount) {
        setState(() {
          _saving = false;
          if (_error?.startsWith('草稿保存失败') == true) _error = null;
        });
      }
    });
    _saveQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<bool> _saveDraft() async {
    _saveTimer?.cancel();
    if (_restoreFailed) return true;
    try {
      await _enqueueSave(_controller.text, _revision);
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '草稿保存失败，正文仍保留：$error';
        });
      }
      return false;
    }
  }

  Future<void> _retryRestore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _restoreFailed = false;
      _error = null;
    });
    _restoreFuture = _restore();
    await _restoreFuture;
  }

  Future<void> _close() async {
    if (_closing || _submitting) return;
    setState(() => _closing = true);
    await _restoreFuture;
    var saved = false;
    if (_submitted) {
      try {
        await ref.read(draftStoreProvider).remove(_location);
        saved = true;
      } catch (error) {
        if (mounted) setState(() => _error = '日志已提交，本机草稿清理失败：$error');
      }
    } else {
      saved = await _saveDraft();
    }
    if (!mounted) return;
    if (!saved) {
      setState(() => _closing = false);
      return;
    }
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).pop(_submitted);
  }

  Future<void> _submit() async {
    if (_loading ||
        _restoreFailed ||
        _submitting ||
        _submitted ||
        _readOnly ||
        !_isCurrentAccount) {
      return;
    }
    if (_controller.text.trim().isEmpty) {
      setState(() => _error = '请填写今日工作');
      return;
    }
    if (!_hasSubmittedBefore && !canInitiallySubmitDiaryOn(_date)) {
      setState(() => _error = '仅可首次提交今天、昨天或前天的日志');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (!await _saveDraft() || !mounted || !_isCurrentAccount) return;
      final text = _controller.text;
      final result = await ref
          .read(repositoryProvider)
          .execute(
            'logs',
            Command(
              _hasSubmittedBefore ? 'update-content' : 'submit',
              {
                if (_hasSubmittedBefore) ...{
                  'id': _recordId,
                  'work': text,
                } else ...{
                  '今日工作': text,
                  'businessDate': _dayKey,
                  'title': '${_date.month}月${_date.day}日工作日志',
                },
              },
              version: _version,
              idempotencyKey:
                  'diary-$_accountId-$_dayKey-${DateTime.now().microsecondsSinceEpoch}',
            ),
          );
      if (!mounted) return;
      if (!_isCurrentAccount) {
        setState(() => _error = '账号已切换，请返回后核对日志状态');
        return;
      }
      _recordId = result.id;
      _version = result.version;
      refreshBusiness(ref);
      ref.invalidate(todayDraftProvider(_accountId));
      ref.invalidate(recordsProvider('logs'));
      ref.invalidate(datedRecordsProvider('logs'));
      ref.invalidate(logDayRecordsProvider);
      _submitted = true;
      try {
        await ref.read(draftStoreProvider).remove(_location);
      } catch (cleanupError) {
        setState(() {
          _closing = false;
          _error = '日志已提交，本机草稿清理失败：$cleanupError';
        });
        return;
      }
      if (mounted) {
        setState(() {
          _closing = true;
          _allowPop = true;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (error is DiarySubmitFailure) {
        _recordId = error.draftId;
        _version = error.draftVersion;
        try {
          await _enqueueSave(_controller.text, _revision);
        } catch (saveError) {
          if (mounted) setState(() => _error = '提交失败且草稿保存失败，正文仍保留：$saveError');
        }
      }
      if (mounted && _isCurrentAccount) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final colors = Theme.of(context).colorScheme;
    final view = View.of(context);
    final scale = view.devicePixelRatio;
    final screenHeight = view.physicalSize.height / scale;
    final keyboardHeight = view.viewInsets.bottom / scale;
    final heightBudget = math.max(0.0, screenHeight * 2 / 3 - keyboardHeight);
    final height = math.min(heightBudget, MediaQuery.sizeOf(context).height);
    final compact = height < 210;
    final active = session.id == _accountId && session.token == _sessionToken && session.canReadBusiness;

    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: SizedBox(
        height: height,
        child: SafeArea(
          top: false,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: SunnyPalette.paper),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '今日工作',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: SunnyPalette.ink,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _dayKey,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: SunnyPalette.muted,
                                    letterSpacing: .2,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      _ComposerIconAction(
                        label: '关闭',
                        icon: Icons.close_rounded,
                        onPressed: _close,
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: const Color(0xFFD8C8B5).withValues(alpha: .55),
                ),
                if (!active)
                  Expanded(
                    child: Center(
                      child: Text(
                        '账号权限已变化，请关闭后重新打开',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else if (_readOnly)
                  Expanded(
                    child: Center(
                      child: Text(
                        '首次提交已满24小时，日志仅可查看',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else if (height < 128)
                  Expanded(
                    child: Center(
                      child: Text(
                        '键盘占用空间较大，请收起键盘后继续编辑',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  )
                else if (compact)
                  _compactEditor(context)
                else
                  Expanded(child: _fullEditor(context)),
                if (active && height >= 210)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      children: [
                        Expanded(child: _saveState(context)),
                        if (_restoreFailed)
                          _ComposerAction(
                            label: '重试读取',
                            icon: Icons.refresh_rounded,
                            onPressed: _retryRestore,
                            emphasized: true,
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
  }

  Widget _fullEditor(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
    child: Stack(
      children: [
        Positioned.fill(
          child: _LinedNotePaper(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _changed,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              textInputAction: TextInputAction.newline,
              enabled:
                  !_loading &&
                  !_restoreFailed &&
                  !_submitted &&
                  !_closing &&
                  !_readOnly,
              style: const TextStyle(
                color: SunnyPalette.ink,
                fontSize: 16,
                height: 1.72,
              ),
              cursorColor: SunnyPalette.primaryStrong,
              decoration: InputDecoration(
                hintText: _loading ? '正在恢复本机草稿…' : '写下今天完成的工作',
                hintStyle: const TextStyle(
                  color: SunnyPalette.muted,
                  fontSize: 16,
                  height: 1.72,
                ),
                contentPadding: const EdgeInsets.fromLTRB(18, 12, 16, 68),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: _ComposerAction(
            label: _submitting
                ? '提交中'
                : _hasSubmittedBefore
                ? '提交修改'
                : '提交',
            icon: Icons.arrow_upward_rounded,
            onPressed:
                _submitting ||
                    _loading ||
                    _submitted ||
                    _restoreFailed ||
                    _readOnly
                ? null
                : _submit,
            emphasized: true,
          ),
        ),
      ],
    ),
  );

  Widget _compactEditor(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
    child: SizedBox(
      height: 54,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _changed,
              maxLines: 1,
              enabled:
                  !_loading &&
                  !_restoreFailed &&
                  !_submitted &&
                  !_closing &&
                  !_readOnly,
              decoration: InputDecoration(
                hintText: '今日工作',
                filled: true,
                fillColor: SunnyPalette.paper,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFD8C8B5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFD8C8B5)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ComposerIconAction(
            label: '提交',
            icon: Icons.arrow_upward_rounded,
            onPressed: _submitting || _loading || _submitted ? null : _submit,
          ),
        ],
      ),
    ),
  );

  Widget _saveState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label =
        _error ??
        (_loading
            ? '正在读取草稿'
            : _saving
            ? '自动保存中'
            : _keyboardCollapsedForSpace
            ? '键盘已收起，可继续编辑'
            : '自动保存到此设备');
    return Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: _error == null ? colors.onSurfaceVariant : colors.error,
      ),
    );
  }
}

class _LinedNotePaper extends StatelessWidget {
  const _LinedNotePaper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF2),
        border: Border.all(color: const Color(0xFFD8C8B5)),
      ),
      child: CustomPaint(painter: const _LinedPaperPainter(), child: child),
    ),
  );
}

class _LinedPaperPainter extends CustomPainter {
  const _LinedPaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final horizontal = Paint()
      ..color = const Color(0x309B7B5D)
      ..strokeWidth = 1;
    for (var y = 38.0; y < size.height - 10; y += 28) {
      canvas.drawLine(Offset(14, y), Offset(size.width - 14, y), horizontal);
    }
    final margin = Paint()
      ..color = const Color(0x2ACB7A67)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(14, 0), Offset(14, size.height), margin);
  }

  @override
  bool shouldRepaint(covariant _LinedPaperPainter oldDelegate) => false;
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: emphasized ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_labelIsSubmit(label)) ...[
                    Icon(icon, size: 18, color: colors.onPrimaryContainer),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: emphasized
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _labelIsSubmit(String value) => value == '提交' || value == '提交中';
}

class _ComposerIconAction extends StatelessWidget {
  const _ComposerIconAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: colors.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                icon,
                color: onPressed == null
                    ? colors.onSurfaceVariant.withValues(alpha: .45)
                    : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
