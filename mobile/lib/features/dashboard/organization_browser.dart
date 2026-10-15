import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/features/dashboard/management_page.dart';

class OrganizationBrowser extends ConsumerStatefulWidget {
  const OrganizationBrowser({super.key});
  @override
  ConsumerState<OrganizationBrowser> createState() =>
      _OrganizationBrowserState();
}

class _OrganizationBrowserState extends ConsumerState<OrganizationBrowser> {
  String search = '';
  Widget person(Record p) => ListTile(
    leading: CircleAvatar(
      child: Text(p.title.isEmpty ? '人' : p.title.substring(0, 1)),
    ),
    title: Text(p.title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push('/me/team/${encode(p.id)}'),
  );
  @override
  Widget build(BuildContext context) {
    if (!ref.watch(sessionProvider).manager) {
      return const PageFrame(
        title: '组织与成员',
        child: EmptyIllustration(showCharacter: false, title: '无权访问'),
      );
    }
    return PageFrame(
      title: '组织与成员',
      child: PageBody(
        children: [
          const Text(
            '授权范围 › 部门 › 团队',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              hintText: '搜索姓名、部门或团队',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
          const SizedBox(height: 16),
          ref
              .watch(organizationTreeProvider)
              .when(
                skipLoadingOnRefresh: false,
                skipLoadingOnReload: false,
                loading: () => const LoadingSkeleton(),
                error: (e, _) => RecordFailure(
                  e,
                  retry: () => ref.invalidate(organizationTreeProvider),
                ),
                data: (tree) {
                  final departments = organizationUnits(tree, 'departments'),
                      teams = organizationUnits(tree, 'teams');
                  final people = (tree.fields['people'] as List? ?? [])
                      .whereType<Record>()
                      .toList();
                  bool matches(Record p) =>
                      '${p.title}${organizationName(tree, 'departments', p.fields['department_id'])}${organizationName(tree, 'teams', p.fields['team_id'])}'
                          .contains(search);
                  final shown = people.where(matches).toList();
                  final visibleDepartments = departments
                      .where(
                        (d) =>
                            search.isEmpty ||
                            '${d['name']}'.contains(search) ||
                            teams.any(
                              (t) =>
                                  t['department_id'] == d['id'] &&
                                  '${t['name']}'.contains(search),
                            ) ||
                            shown.any(
                              (p) => p.fields['department_id'] == d['id'],
                            ),
                      )
                      .toList();
                  final unassigned = shown
                      .where(
                        (p) => !departments.any(
                          (d) => d['id'] == p.fields['department_id'],
                        ),
                      )
                      .toList();
                  if (visibleDepartments.isEmpty && unassigned.isEmpty) {
                    return const EmptyIllustration(
                      title: '暂无匹配组织或成员',
                      subtitle: '仅显示当前授权范围，可调整搜索条件',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${departments.length} 个可见部门 · ${people.length} 位成员',
                      ),
                      const SizedBox(height: 12),
                      for (final d in visibleDepartments) ...[
                        PaperSurface(
                          padding: EdgeInsets.zero,
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            title: Text('${d['name']}'),
                            subtitle: Text(
                              '${people.where((p) => p.fields['department_id'] == d['id']).length} 位可见成员',
                            ),
                            children: [
                              for (final team in teams.where(
                                (t) => t['department_id'] == d['id'],
                              ))
                                ExpansionTile(
                                  initiallyExpanded: true,
                                  title: Text('${team['name']}'),
                                  children: [
                                    for (final p in shown.where(
                                      (p) =>
                                          p.fields['department_id'] ==
                                              d['id'] &&
                                          p.fields['team_id'] == team['id'],
                                    ))
                                      person(p),
                                    if (!shown.any(
                                      (p) =>
                                          p.fields['department_id'] ==
                                              d['id'] &&
                                          p.fields['team_id'] == team['id'],
                                    ))
                                      const ListTile(title: Text('暂无匹配成员')),
                                  ],
                                ),
                              for (final p in shown.where(
                                (p) =>
                                    p.fields['department_id'] == d['id'] &&
                                    !teams.any(
                                      (t) =>
                                          t['department_id'] == d['id'] &&
                                          t['id'] == p.fields['team_id'],
                                    ),
                              ))
                                person(p),
                              if (!teams.any(
                                    (t) => t['department_id'] == d['id'],
                                  ) &&
                                  !shown.any(
                                    (p) => p.fields['department_id'] == d['id'],
                                  ))
                                const ListTile(title: Text('暂无团队或成员')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (unassigned.isNotEmpty)
                        PaperSurface(
                          padding: EdgeInsets.zero,
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            title: const Text('待分配或归属不可见'),
                            children: [for (final p in unassigned) person(p)],
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
