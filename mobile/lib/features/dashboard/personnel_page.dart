import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

/// Read-only personnel overview grouped by the server-provided department.
class PersonnelPage extends ConsumerStatefulWidget {
  const PersonnelPage({super.key});

  @override
  ConsumerState<PersonnelPage> createState() => _PersonnelPageState();
}

class _PersonnelPageState extends ConsumerState<PersonnelPage> {
  String search = '';
  String department = '全部部门';

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(sessionProvider);
    final people = ref.watch(recordsProvider('organization'));
    return PageFrame(
      title: '人员展示',
      actions: [
        IconButton(
          tooltip: '刷新人员数据',
          onPressed: () => ref.invalidate(recordsProvider('organization')),
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: PageBody(
        children: [
          PaperSurface(
            color: DogBrandPalette.surface,
            borderColor: DogBrandPalette.line,
            child: Row(
              children: [
                const DogAvatar(index: DogAssets.friendly, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    current.manager ? '按部门浏览团队成员' : '查看授权范围内的成员信息',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              hintText: '搜索姓名或部门',
              prefixIcon: Icon(Icons.search),
              filled: true,
              fillColor: DogBrandPalette.surface,
            ),
            onChanged: (value) => setState(() => search = value.trim()),
          ),
          const SizedBox(height: 16),
          people.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (page) {
              final departments = {
                '全部部门',
                ...page.items.map(
                  (p) =>
                      '${p.fields['departmentName'] ?? p.fields['department'] ?? '未分组'}',
                ),
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PremiumDropdownField<String>(
                  key: ValueKey('personnel-department:$department'),
                  initialValue: departments.contains(department)
                      ? department
                      : '全部部门',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '部门筛选'),
                  items: [
                    for (final name in departments)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) => setState(() => department = value!),
                ),
              );
            },
          ),
          people.when(
            loading: () => const LoadingSkeleton(),
            error: (error, _) => RecordFailure(
              error,
              retry: () => ref.invalidate(recordsProvider('organization')),
            ),
            data: (page) {
              final visible = page.items.where((person) {
                final personDepartment =
                    '${person.fields['departmentName'] ?? person.fields['department'] ?? '未分组'}';
                return (department == '全部部门' ||
                        personDepartment == department) &&
                    '${person.title}$personDepartment'.toLowerCase().contains(
                      search.toLowerCase(),
                    );
              }).toList();
              if (visible.isEmpty) {
                return const EmptyIllustration(
                  title: '暂无匹配人员',
                  subtitle: '可以调整搜索条件',
                );
              }
              final groups = <String, List<Record>>{};
              for (final person in visible) {
                final department =
                    '${person.fields['departmentName'] ?? person.fields['department'] ?? '未分组'}';
                groups.putIfAbsent(department, () => []).add(person);
              }
              final names = groups.keys.toList()..sort();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${visible.length} 位可见成员 · ${names.length} 个部门',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  for (final department in names) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Text(
                        department,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    for (final person in groups[department]!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PersonnelCard(
                          person: person,
                          onTap: () {
                            if (current.manager && person.id != current.id) {
                              final month = ref.read(
                                memberCalendarDateProvider(person.id),
                              );
                              unawaited(
                                ref.read(
                                  calendarMonthTasksProvider((
                                    person.id,
                                    month.year * 12 + month.month - 1,
                                  )).future,
                                ),
                              );
                              context.push('/me/team/${encode(person.id)}');
                            } else {
                              context.push('/me/profile');
                            }
                          },
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
          const DemoLabel(),
        ],
      ),
    );
  }
}

class _PersonnelCard extends StatelessWidget {
  const _PersonnelCard({required this.person, required this.onTap});

  final Record person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fields = person.fields;
    final department =
        '${fields['departmentName'] ?? fields['department'] ?? '未分组'}';
    final taskCount = fields['participatingTaskCount'] as num?;
    final activeCount = fields['activeTaskCount'] as num?;
    final logState = switch (fields['todayLogStatus']) {
      'SUBMITTED' => '今日日志已提交',
      'MISSING' => '今日日志未提交',
      '今日日志已提交' => '今日日志已提交',
      '今日日志待提交' => '今日日志未提交',
      _ => '今日日志状态未知',
    };
    final taskState = activeCount == null
        ? '任务状态未知'
        : activeCount > 0
        ? '未结束任务 ${activeCount.toInt()}'
        : '暂无未结束任务';
    return PaperSurface(
      color: DogBrandPalette.surface,
      borderColor: DogBrandPalette.line,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProtectedAvatar(
            name: person.title,
            attachmentId: fields['avatarAttachmentId'] as String?,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(department, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AppLabelBadge(
                      taskCount == null ? '参与任务数未知' : '参与任务 ${taskCount.toInt()}',
                      color: SunnyPalette.orange,
                      compact: true,
                    ),
                    AppLabelBadge(
                      logState,
                      color: SunnyPalette.mint,
                      compact: true,
                    ),
                    AppLabelBadge(
                      taskState,
                      color: SunnyPalette.purple,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
    );
  }
}
