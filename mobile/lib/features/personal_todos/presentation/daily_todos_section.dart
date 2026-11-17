import '../../../core/state/providers.dart';
import '../../../shared/premium_pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/calendar/civil_date.dart';
import '../../calendar/calendar_content.dart';
import 'todo_calendar_source.dart';

/// Uses the company month view, including its gesture surface and day agenda.
class DailyTodosSection extends ConsumerWidget {
  const DailyTodosSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(todoCalendarDateProvider);
    const source = TodoCalendarSource();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '每日事项',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '回到今天',
              onPressed: () =>
                  ref.read(todoCalendarDateProvider.notifier).state =
                      shanghaiToday(),
              icon: const Icon(Icons.today),
            ),
            IconButton(
              tooltip: '刷新事项',
              onPressed: () => source.refresh(ref),
              icon: const Icon(Icons.refresh),
            ),
            TextButton.icon(
              onPressed: () => source.create(context, ref, selected),
              icon: const Icon(Icons.add),
              label: const Text('新增事项'),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('todo-quick-date'),
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(
              '${selected.year}年${selected.month}月${selected.day}日  ▾',
            ),
            onPressed: () async {
              final epoch = ref.read(sessionEpochProvider);
              final date = await showPremiumDatePicker(
                context,
                initial: selected,
                firstDate: DateTime(source.firstYear),
                lastDate: DateTime(source.lastYear, 12, 31),
                title: '跳转到日期',
              );
              if (context.mounted &&
                  epoch == ref.read(sessionEpochProvider) &&
                  date != null) {
                ref.read(todoCalendarDateProvider.notifier).state = date;
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        CalendarContent(
          monthOnly: true,
          source: source,
          dateStateProvider: todoCalendarDateProvider,
        ),
      ],
    );
  }
}
