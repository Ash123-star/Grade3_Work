import 'package:flutter/material.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/theme/home_paper_theme.dart';

/// Presentation-only organization identity. Names never replace a supplied ID.
class PersonOrganization {
  PersonOrganization(this.person);
  final Record person;

  String get department => _name(
    person.fields['departmentName'] ?? person.fields['department'],
    person.subtitle.isEmpty ? '未分配部门' : person.subtitle,
  );
  String get team => _name(
    person.fields['teamName'] ??
        person.fields['team_name'] ??
        person.fields['team'],
    '未分配团队',
  );
  String get departmentKey => _id('DEPARTMENT', department);
  String get teamKey => _id('TEAM', team);
  String get branchKey => '$departmentKey\u0000$teamKey';
  String get path => '$department / $team';

  bool matches(String query) => '${person.title} $department $team'
      .toLowerCase()
      .contains(query.toLowerCase());

  String _name(Object? value, String fallback) {
    final text = value is Map ? value['name'] : value;
    return text is String && text.trim().isNotEmpty ? text.trim() : fallback;
  }

  String _id(String kind, String fallback) {
    final field = kind == 'DEPARTMENT' ? 'departmentId' : 'teamId';
    final snake = kind == 'DEPARTMENT' ? 'department_id' : 'team_id';
    final direct = person.fields[field] ?? person.fields[snake];
    if (direct is String && direct.isNotEmpty) return 'id:$direct';
    final path = person.fields['organizationPath'];
    if (path is List) {
      for (final node in path) {
        if (node is Map && node['kind'] == kind) {
          final id = node['id'];
          if (id is String && id.isNotEmpty) return 'id:$id';
        }
      }
    }
    return 'name:$fallback';
  }
}

Map<String, Map<String, List<Record>>> groupOrganizationPeople(
  Iterable<Record> people,
) {
  final groups = <String, Map<String, List<Record>>>{};
  for (final person in people) {
    final org = PersonOrganization(person);
    groups
        .putIfAbsent(org.departmentKey, () => <String, List<Record>>{})
        .putIfAbsent(org.teamKey, () => <Record>[])
        .add(person);
  }
  return groups;
}

/// The directory owns only hierarchy; callers keep their existing person rows,
/// authorization, loading, pagination and selection behavior.
class OrganizationDirectory extends StatelessWidget {
  const OrganizationDirectory({
    super.key,
    required this.people,
    required this.expandedDepartments,
    required this.expandedTeams,
    required this.onDepartmentToggle,
    required this.onTeamToggle,
    required this.personBuilder,
    this.keyPrefix = 'directory',
    this.showCounts = true,
  });

  final List<Record> people;
  final Set<String> expandedDepartments, expandedTeams;
  final ValueChanged<String> onDepartmentToggle, onTeamToggle;
  final Widget Function(Record) personBuilder;
  final String keyPrefix;
  final bool showCounts;

  @override
  Widget build(BuildContext context) {
    final groups = groupOrganizationPeople(people);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final department in groups.entries) ...[
          _DirectoryNode(
            key: ValueKey('$keyPrefix-department-${department.key}'),
            name: PersonOrganization(
              department.value.values.first.first,
            ).department,
            count: showCounts
                ? department.value.values.fold<int>(
                    0,
                    (n, people) => n + people.length,
                  )
                : null,
            expanded: expandedDepartments.contains(department.key),
            onTap: () => onDepartmentToggle(department.key),
          ),
          if (expandedDepartments.contains(department.key))
            _DirectoryIndent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final team in department.value.entries) ...[
                    _DirectoryNode(
                      key: ValueKey(
                        '$keyPrefix-team-${department.key}-${team.key}',
                      ),
                      name: PersonOrganization(team.value.first).team,
                      count: showCounts ? team.value.length : null,
                      expanded: expandedTeams.contains(
                        PersonOrganization(team.value.first).branchKey,
                      ),
                      onTap: () => onTeamToggle(
                        PersonOrganization(team.value.first).branchKey,
                      ),
                    ),
                    if (expandedTeams.contains(
                      PersonOrganization(team.value.first).branchKey,
                    ))
                      _DirectoryIndent(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: team.value.map(personBuilder).toList(),
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _DirectoryNode extends StatelessWidget {
  const _DirectoryNode({
    super.key,
    required this.name,
    required this.expanded,
    required this.onTap,
    this.count,
  });
  final String name;
  final int? count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paper = HomePaperTokens.of(context);
    return Semantics(
      expanded: expanded,
      child: ListTile(
        minTileHeight: 60,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        minLeadingWidth: 20,
        horizontalTitleGap: 8,
        leading: Icon(
          expanded
              ? Icons.keyboard_arrow_down_rounded
              : Icons.chevron_right_rounded,
          size: 20,
          color: paper.muted,
        ),
        title: Text(
          name,
          style: paper.body(15).copyWith(fontWeight: FontWeight.w600),
        ),
        trailing: count == null
            ? null
            : Text('$count人', style: paper.body(11, color: paper.muted)),
        onTap: onTap,
      ),
    );
  }
}

class _DirectoryIndent extends StatelessWidget {
  const _DirectoryIndent({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 12),
    padding: const EdgeInsets.only(left: 8),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: HomePaperTokens.of(context).line)),
    ),
    child: child,
  );
}
