import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/failure.dart';
import 'package:pandora_mobile/core/providers.dart';
import 'package:pandora_mobile/data/memory_client.dart';
import 'package:pandora_mobile/data/models.dart';
import 'package:pandora_mobile/features/ai_map_page.dart';

class StateClient implements MemoryClient {
  StateClient(this.analysis, {this.failure});
  final Map<String, dynamic> analysis;
  final ApiFailure? failure;

  @override
  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    if (path == '/ai-maps/development') {
      if (failure != null) throw failure!;
      return {
        'scopes': [
          {
            'domain': 'PERSONAL',
            'scopeType': 'SELF',
            'scopeId': 'u1',
            'label': '个人',
          },
        ],
        'analysis': analysis,
      };
    }
    if (path == '/ai-memories/knowledge-status') {
      return {
        'memories': 2,
        'indexedMemories': 1,
        'indexingMemories': 1,
        'candidates': 1,
      };
    }
    if (path == '/ai-memories/preferences/me') {
      return {'version': 1, 'explicit_goals': '', 'response_preferences': ''};
    }
    throw StateError('Unexpected request: $method $path');
  }
}

void main() {
  testWidgets('live map shows missing evidence and graph degradation', (
    tester,
  ) async {
    if (AppConfig.mock) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = StateClient({
      'id': 'analysis-1',
      'state': 'SUCCEEDED',
      'output': {
        'summary': '本次没有检索到相关有效证据',
        'basisQuality': 'INSUFFICIENT',
        'generatedAt': '2026-10-09T00:00:00Z',
        'retrieval': {'degradedReason': '图谱暂不可用，使用文本证据'},
        'facts': [],
        'directions': [],
        'suggestions': [],
        'gaps': ['缺少与目标相关的经历与成果'],
      },
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => const Session()),
          memoryClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(home: AiPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('更新中 1 条'), findsOneWidget);
    expect(find.textContaining('待确认 1 条'), findsOneWidget);
    expect(find.textContaining('本次没有检索到相关有效证据'), findsOneWidget);
    expect(find.text('图谱暂不可用，使用文本证据'), findsOneWidget);
    expect(find.textContaining('缺少与目标相关的经历与成果'), findsOneWidget);
    expect(find.text('从执行任务，走向独立推进'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live map shows model and stale-source failures without output', (
    tester,
  ) async {
    if (AppConfig.mock) return;
    for (final state in ['FAILED', 'STALE']) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => const Session()),
            memoryClientProvider.overrideWithValue(
              StateClient({
                'id': 'analysis-2',
                'state': state,
                'error': state == 'FAILED' ? 'DeepSeek 尚未配置' : '来源已变化，请更新分析',
              }),
            ),
          ],
          child: const MaterialApp(home: AiPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(state == 'FAILED' ? 'DeepSeek 尚未配置' : '来源已变化，请更新分析'),
        findsOneWidget,
      );
      expect(find.text('从执行任务，走向独立推进'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('live map reports scope denial', (tester) async {
    if (AppConfig.mock) return;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => const Session()),
          memoryClientProvider.overrideWithValue(
            StateClient(
              {},
              failure: const ApiFailure(FailureKind.forbidden, '你没有访问这项内容的权限'),
            ),
          ),
        ],
        child: const MaterialApp(home: AiPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('你没有访问这项内容的权限'), findsOneWidget);
    expect(find.text('从执行任务，走向独立推进'), findsNothing);
  });
}
