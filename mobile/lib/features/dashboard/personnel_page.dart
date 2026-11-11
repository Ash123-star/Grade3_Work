import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/tenure.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/shared/organization_directory.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

/// Read-only personnel records in the authorized department/team directory.
class PersonnelPage extends ConsumerStatefulWidget {
  const PersonnelPage({super.key});

  @override
  ConsumerState<PersonnelPage> createState() => _PersonnelPageState();
}

class _PersonnelPageState extends ConsumerState<PersonnelPage> {
  String search = '';
  final expandedDepartments = <String>{};
  final expandedTeams = <String>{};
  String expandedSearch = '';

  void toggle(Set<String> nodes, String id) => setState(() {
    if (!nodes.remove(id)) nodes.add(id);
  });

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
          TextField(
            decoration: const InputDecoration(
              hintText: '搜索姓名、部门或团队',
              prefixIcon: Icon(Icons.search),
              filled: true,
              fillColor: DogBrandPalette.surface,
            ),
            onChanged: (value) => setState(() => search = value.trim()),
          ),
          const SizedBox(height: 16),
          people.when(
            loading: () => const LoadingSkeleton(),
            error: (error, _) => RecordFailure(
              error,
              retry: () => ref.invalidate(recordsProvider('organization')),
            ),
            data: (page) {
              final visible = page.items
                  .where((person) => PersonOrganization(person).matches(search))
                  .toList();
              if (visible.isEmpty) {
                expandedSearch = search;
                return const EmptyIllustration(
                  title: '暂无匹配人员',
                  subtitle: '可以调整搜索条件',
                );
              }
              final groups = groupOrganizationPeople(visible);
              if (search.isNotEmpty && expandedSearch != search) {
                for (final person in visible) {
                  final org = PersonOrganization(person);
                  expandedDepartments.add(org.departmentKey);
                  expandedTeams.add(org.branchKey);
                }
                expandedSearch = search;
              } else if (search.isEmpty) {
                expandedSearch = '';
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${visible.length} 位可见成员 · ${groups.length} 个部门',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  OrganizationDirectory(
                    keyPrefix: 'personnel',
                    people: visible,
                    expandedDepartments: expandedDepartments,
                    expandedTeams: expandedTeams,
                    onDepartmentToggle: (id) => toggle(expandedDepartments, id),
                    onTeamToggle: (id) => toggle(expandedTeams, id),
                    personBuilder: (person) => Padding(
                      key: ValueKey('personnel-record-${person.id}'),
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
                          } else if (person.id == current.id) {
                            context.push('/me/profile');
                          } else {
                            showTuantuanBottomSheet<void>(
                              context: context,
                              useSafeArea: true,
                              builder: (_) => Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      person.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      '入职日期：${employmentDateLabel(person.fields['employmentStartDate'])}',
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '工龄：${tenureLabel(parseEmploymentDate(person.fields['employmentStartDate']), shanghaiWallTime(DateTime.now()))}',
                                    ),
                                    const SizedBox(height: 20),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('收起'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
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
                      taskCount == null
                          ? '参与任务数未知'
                          : '参与任务 ${taskCount.toInt()}',
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
