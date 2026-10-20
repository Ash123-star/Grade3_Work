export 'paper_layout.dart'
    show TuantuanDialog, TuantuanSheet, showTuantuanBottomSheet;
export 'page_states.dart';
export 'sunny_button.dart';
import 'page_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/config.dart';
import 'paper_layout.dart';
import 'generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';

String encode(String value) => Uri.encodeComponent(value);
void openList(BuildContext context, String resource) =>
    context.push('/list/${encode(resource)}');
void openItem(
  BuildContext context,
  String resource,
  String id, {
  String? ownerId,
}) => context.push(
  '/item/${encode(resource)}/${encode(id)}${ownerId == null ? '' : '?ownerId=${encode(ownerId)}'}',
);
void openForm(
  BuildContext context,
  String form, {
  String? id,
  int? version,
  bool restoreDiaryDraft = false,
}) {
  final query = [
    if (id != null) 'id=${encode(id)}',
    if (id != null) 'version=${version ?? 1}',
    if (restoreDiaryDraft) 'draftSource=diary',
  ].join('&');
  context.push('/form/$form${query.isEmpty ? '' : '?$query'}');
}

void notice(BuildContext context, String text, {bool success = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: success
                ? const Color(0xFFB9DED0)
                : Theme.of(context).colorScheme.error.withValues(alpha: .28),
          ),
        ),
        backgroundColor: success
            ? const Color(0xFFEAF6F0)
            : Theme.of(context).colorScheme.errorContainer,
        elevation: 2,
        closeIconColor: Theme.of(context).colorScheme.onSurface,
        showCloseIcon: true,
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_outline : Icons.error_outline,
              color: success
                  ? SunnyPalette.successInk
                  : Theme.of(context).colorScheme.error,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: success
                      ? const Color(0xFF246447)
                      : Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );

class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.bottomPadding = 24,
    this.controller,
    this.header,
  });
  final List<Widget> children;
  final double bottomPadding;
  final ScrollController? controller;
  final Widget? header;
  @override
  Widget build(BuildContext context) {
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
          children: [?header, ...children],
        ),
      ),
    );
    return TuantuanPaperBackdrop(child: content);
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.showTitle = true,
    this.actions,
    this.fab,
    this.bottom,
  });
  final String title;
  final Widget child;
  final bool showTitle;
  final List<Widget>? actions;
  final Widget? fab;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();
    final headerContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Row(
              children: [
                const DogAvatar(index: DogAssets.friendly, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          if (canGoBack || (actions?.isNotEmpty ?? false))
            ConstrainedBox(
              key: const ValueKey('page-scroll-actions'),
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canGoBack) const BackButton(),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions ?? const [],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    final header = showTitle || canGoBack || (actions?.isNotEmpty ?? false)
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: headerContent,
          )
        : const SizedBox.shrink();
    final content = child;
    return Scaffold(
      body: SafeArea(
        child: content is PageBody
            ? PageBody(
                controller: content.controller,
                bottomPadding: content.bottomPadding,
                header: header,
                children: content.children,
              )
            : TuantuanPaperBackdrop(
                child: Column(
                  children: [header, Expanded(child: content)],
                ),
              ),
      ),
      floatingActionButton: fab,
      bottomNavigationBar: bottom == null
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: bottom,
            ),
    );
  }
}

class DemoLabel extends StatelessWidget {
  const DemoLabel({super.key});
  @override
  Widget build(BuildContext context) => AppConfig.mock
      ? const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '演示数据 · 未连接企业服务',
              style: TextStyle(fontSize: 11, color: CuteTokens.muted),
            ),
          ),
        )
      : const SizedBox.shrink();
}

class RecordList extends ConsumerWidget {
  const RecordList(
    this.resource, {
    super.key,
    this.limit,
    this.onTap,
    this.dated = false,
  });
  final String resource;
  final int? limit;
  final bool dated;
  final void Function(Record)? onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = dated
        ? datedRecordsProvider(resource)
        : recordsProvider(resource);
    return ref
        .watch(provider)
        .when(
          loading: () => const LoadingSkeleton(),
          error: (e, s) =>
              ErrorPanel(e.toString(), retry: () => ref.invalidate(provider)),
          data: (page) => page.items.isEmpty
              ? const EmptyIllustration()
              : Column(
                  children: page.items
                      .take(limit ?? page.items.length)
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TuantuanRecordCard(
                            icon: _resourceIcon(resource),
                            accent: _resourceAccent(context, resource),
                            title: item.title,
                            subtitle: item.subtitle,
                            onTap: () => onTap != null
                                ? onTap!(item)
                                : openItem(context, resource, item.id),
                          ),
                        ),
                      )
                      .toList(),
                ),
        );
  }
}

String _resourceIcon(String resource) => switch (resource) {
  'tasks' => 'task',
  'logs' || 'logs/subordinates' => 'log',
  'notifications' => 'notification',
  'reviews' => 'approval',
  'organization' => 'members',
  'dashboard/company' || 'dashboard/personal' => 'mindmap',
  _ => 'report',
};

Color _resourceAccent(BuildContext context, String resource) =>
    switch (resource) {
      'tasks' => SunnyPalette.orange,
      'logs' || 'logs/subordinates' => SunnyPalette.coral,
      'notifications' => SunnyPalette.blue,
      'reviews' => SunnyPalette.purple,
      'organization' => SunnyPalette.primaryContainer,
      _ => Theme.of(context).colorScheme.surface,
    };

class DateControls extends ConsumerWidget {
  const DateControls({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider),
        period = ref.watch(periodProvider);
    void move(int direction) =>
        ref.read(selectedDateProvider.notifier).state = period == '月'
        ? DateTime(date.year, date.month + direction, 1)
        : date.add(Duration(days: direction * (period == '周' ? 7 : 1)));
    final tabs = PillTabs(
      labels: const ['日', '周', '月'],
      selected: ['日', '周', '月'].indexOf(period),
      onChanged: (i) =>
          ref.read(periodProvider.notifier).state = ['日', '周', '月'][i],
    );
    final today = TextButton.icon(
      onPressed: () =>
          ref.read(selectedDateProvider.notifier).state = DateTime.now(),
      icon: const Icon(Icons.today_outlined, size: 18),
      label: const Text('今天'),
    );
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上一个$period',
              onPressed: () => move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton(
                onPressed: () async {
                  final next = await showCalendarDateWheel(
                    context: context,
                    initialDate: date,
                  );
                  if (next != null) {
                    ref.read(selectedDateProvider.notifier).state = next;
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          period == '月'
                              ? '${date.year}年${date.month}月'
                              : '${date.month}月${date.day}日${period == '周' ? ' · 本周' : ''}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: CuteTokens.ink,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: CuteTokens.ink),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '下一个$period',
              onPressed: () => move(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (period == '月')
          Row(
            children: [
              Expanded(child: tabs),
              const SizedBox(width: 4),
              today,
            ],
          )
        else ...[
          tabs,
          Align(alignment: Alignment.centerRight, child: today),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

Future<DateTime?> showCalendarDateWheel({
  required BuildContext context,
  required DateTime initialDate,
}) {
  var selected = DateTime(initialDate.year, initialDate.month, initialDate.day);
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: 340,
        child: Column(
          children: [
            Expanded(
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  primaryColor: SunnyPalette.primaryStrong,
                ),
                child: CupertinoDatePicker(
                  key: const ValueKey('calendar-date-wheel'),
                  mode: CupertinoDatePickerMode.date,
                  dateOrder: DatePickerDateOrder.ymd,
                  initialDateTime: selected,
                  minimumYear: 2020,
                  maximumYear: 2040,
                  onDateTimeChanged: (value) => selected = value,
                ),
              ),
            ),
            const Divider(height: 1),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('calendar-date-cancel'),
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('取消'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    key: const ValueKey('calendar-date-confirm'),
                    onPressed: () => Navigator.pop(sheetContext, selected),
                    child: const Text('确定'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
