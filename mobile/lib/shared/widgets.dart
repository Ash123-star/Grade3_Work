export 'page_states.dart';
export 'sunny_button.dart';
import 'page_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/config.dart';
import 'paper_layout.dart';
import 'sunny_widgets.dart';
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
}) => context.push(
  '/form/$form${id == null ? '' : '?id=${encode(id)}&version=${version ?? 1}'}',
);
void notice(BuildContext context, String text, {bool success = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: success
            ? Theme.of(context).colorScheme.tertiaryContainer
            : null,
        content: success
            ? Row(
                children: [
                  const WorkBuddy(size: 28, pose: BuddyPose.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              )
            : Text(text),
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
  Widget build(BuildContext context) => Align(
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
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.fab,
    this.bottom,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? fab;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();
    final header = canGoBack || (actions?.isNotEmpty ?? false)
        ? ConstrainedBox(
            key: const ValueKey('page-scroll-actions'),
            constraints: const BoxConstraints(minHeight: 48),
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
          )
        : null;
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
            : header == null
            ? content
            : NestedScrollView(
                headerSliverBuilder: (_, _) => [
                  SliverToBoxAdapter(child: header),
                ],
                body: content,
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
                          child: PaperSurface(
                            onTap: () => onTap != null
                                ? onTap!(item)
                                : openItem(context, resource, item.id),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.article_outlined,
                                  color: CuteTokens.muted,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.subtitle,
                                        style: const TextStyle(
                                          color: CuteTokens.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        );
  }
}

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
                  final next = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  if (next != null) {
                    ref.read(selectedDateProvider.notifier).state = next;
                  }
                },
                child: Text(
                  period == '月'
                      ? '${date.year}年${date.month}月'
                      : '${date.month}月${date.day}日${period == '周' ? ' · 本周' : ''}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: CuteTokens.ink,
                  ),
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
        PillTabs(
          labels: const ['日', '周', '月'],
          selected: ['日', '周', '月'].indexOf(period),
          onChanged: (i) =>
              ref.read(periodProvider.notifier).state = ['日', '周', '月'][i],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
