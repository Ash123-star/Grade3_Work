import 'dart:math' as math;
import 'dart:ui';

/// Geometry only: never infers a business relation between unconnected nodes.
class RelationshipLayout {
  RelationshipLayout._(
    this.points,
    this.size,
    this.nodeSize,
    this.cyclic,
    this.isolated,
  );
  final Map<String, Offset> points;
  final Size size, nodeSize;
  final Set<String> cyclic, isolated;

  factory RelationshipLayout.build(
    List<Map<String, dynamic>> nodes,
    List<Map<String, dynamic>> edges, {
    double textScale = 1,
  }) {
    final ids = nodes.map((n) => n['id'] as String).toList()..sort();
    final outgoing = {for (final id in ids) id: <String>{}};
    final connected = <String>{};
    for (final edge in edges) {
      final from = edge['source_id'], to = edge['target_id'];
      if (!outgoing.containsKey(from) || !outgoing.containsKey(to)) continue;
      outgoing[from]!.add(to as String);
      connected.addAll([from as String, to]);
    }

    // Condense strongly connected components so cycles cannot inflate depth.
    final order = <String, int>{}, low = <String, int>{};
    final stack = <String>[], onStack = <String>{};
    final components = <List<String>>[];
    var sequence = 0;
    void visit(String id) {
      order[id] = low[id] = sequence++;
      stack.add(id);
      onStack.add(id);
      final next = outgoing[id]!.toList()..sort();
      for (final target in next) {
        if (!order.containsKey(target)) {
          visit(target);
          low[id] = math.min(low[id]!, low[target]!);
        } else if (onStack.contains(target)) {
          low[id] = math.min(low[id]!, order[target]!);
        }
      }
      if (low[id] == order[id]) {
        final group = <String>[];
        String member;
        do {
          member = stack.removeLast();
          onStack.remove(member);
          group.add(member);
        } while (member != id);
        components.add(group..sort());
      }
    }

    for (final id in ids) {
      if (!order.containsKey(id)) visit(id);
    }
    final groupOf = <String, int>{};
    final cyclic = <String>{};
    for (var i = 0; i < components.length; i++) {
      final group = components[i];
      for (final id in group) {
        groupOf[id] = i;
        if (group.length > 1 || outgoing[id]!.contains(id)) cyclic.add(id);
      }
    }
    final groupEdges = {for (var i = 0; i < components.length; i++) i: <int>{}};
    final indegree = List.filled(components.length, 0);
    for (final id in ids) {
      for (final target in outgoing[id]!) {
        final from = groupOf[id]!, to = groupOf[target]!;
        if (from != to && groupEdges[from]!.add(to)) indegree[to]++;
      }
    }
    final depth = List.filled(components.length, 0);
    final queue = <int>[
      for (var i = 0; i < components.length; i++)
        if (indegree[i] == 0) i,
    ];
    for (var head = 0; head < queue.length; head++) {
      final from = queue[head];
      for (final to in groupEdges[from]!) {
        depth[to] = math.max(depth[to], depth[from] + 1);
        if (--indegree[to] == 0) queue.add(to);
      }
    }
    final isolated = ids.where((id) => !connected.contains(id)).toSet();
    final lastDepth = depth.fold(0, math.max);
    final rowsByDepth = <int, List<String>>{};
    for (final id in ids) {
      final rank = isolated.contains(id) && connected.isNotEmpty
          ? lastDepth + 1
          : depth[groupOf[id]!];
      (rowsByDepth[rank] ??= []).add(id);
    }
    final byId = {for (final node in nodes) node['id']: node};
    final rows = <List<String>>[];
    final ranks = rowsByDepth.keys.toList()..sort();
    for (final rank in ranks) {
      final rowIds = rowsByDepth[rank]!;
      for (var first = 0; first < rowIds.length; first += 3) {
        final row = rowIds.sublist(first, math.min(first + 3, rowIds.length));
        // Center the real goals within each row without altering dependency rank.
        final goals = row.where((id) => byId[id]!['body']['type'] == 'GOAL');
        final others = row.where((id) => byId[id]!['body']['type'] != 'GOAL');
        final arranged = others.toList();
        arranged.insertAll(arranged.length ~/ 2, goals);
        rows.add(arranged);
      }
    }
    final nodeSize = Size(220, 104 + 72 * textScale.clamp(1.0, 3.0));
    final columns = rows.fold(1, (max, row) => math.max(max, row.length));
    final width = math.max(320.0, columns * (nodeSize.width + 32) + 16);
    final points = <String, Offset>{};
    for (var row = 0; row < rows.length; row++) {
      final members = rows[row];
      final left = (width - (members.length * (nodeSize.width + 32) - 32)) / 2;
      for (var col = 0; col < members.length; col++) {
        points[members[col]] = Offset(
          left + col * (nodeSize.width + 32),
          40 + row * (nodeSize.height + 72),
        );
      }
    }
    return RelationshipLayout._(
      points,
      Size(width, math.max(360.0, rows.length * (nodeSize.height + 72) + 8)),
      nodeSize,
      cyclic,
      isolated,
    );
  }
}

String graphTypeLabel(dynamic type) => switch (type) {
  'GOAL' => '目标',
  'RESULT' => '成果',
  'BLOCKER' => '阻碍',
  'RISK' => '风险',
  _ => '类型未确认',
};
