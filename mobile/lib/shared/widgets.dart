import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart';
import '../core/config.dart';
import '../core/providers.dart';
import '../data/models.dart';

String encode(String value) => Uri.encodeComponent(value);
void openList(BuildContext context, String resource) =>
    context.push('/list/${encode(resource)}');
void openItem(BuildContext context, String resource, String id) =>
    context.push('/item/${encode(resource)}/${encode(id)}');
void openForm(
  BuildContext context,
  String form, {
  String? id,
  int? version,
}) => context.push(
  '/form/$form${id == null ? '' : '?id=${encode(id)}&version=${version ?? 1}'}',
);
void notice(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: children,
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
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? fab;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(child: child),
    floatingActionButton: fab,
  );
}

class DemoLabel extends StatelessWidget {
  const DemoLabel({super.key});
  @override
  Widget build(BuildContext context) => AppConfig.mock
      ? const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusPill('演示数据 · 未连接企业服务'),
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
                          child: CuteCard(
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
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上一个$period',
              onPressed: () =>
                  ref.read(selectedDateProvider.notifier).state = period == '月'
                  ? DateTime(date.year, date.month - 1, 1)
                  : date.subtract(Duration(days: period == '周' ? 7 : 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton.icon(
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
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('${date.year}年${date.month}月${date.day}日'),
              ),
            ),
            IconButton(
              tooltip: '下一个$period',
              onPressed: () =>
                  ref.read(selectedDateProvider.notifier).state = period == '月'
                  ? DateTime(date.year, date.month + 1, 1)
                  : date.add(Duration(days: period == '周' ? 7 : 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '日', label: Text('日')),
            ButtonSegment(value: '周', label: Text('周')),
            ButtonSegment(value: '月', label: Text('月')),
          ],
          selected: {period},
          onSelectionChanged: (s) =>
              ref.read(periodProvider.notifier).state = s.first,
        ),
        const SizedBox(height: 8),
        Text(() {
          final range = BusinessRange(date, period);
          final a = range.from.add(const Duration(hours: 8)),
              b = range.to
                  .add(const Duration(hours: 8))
                  .subtract(const Duration(days: 1));
          return '${a.month}月${a.day}日 — ${b.month}月${b.day}日';
        }(), style: const TextStyle(color: CuteTokens.muted)),
        const SizedBox(height: 16),
      ],
    );
  }
}
