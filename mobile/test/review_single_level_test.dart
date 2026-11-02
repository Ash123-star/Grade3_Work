import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';

void main() {
  test('organization changes route to one configured direct manager', () async {
    final store = DemoStore();
    final administrator = MockRepository(
      const Session(id: 'u-admin', role: UserRole.admin),
      store: store,
    );
    final founder = MockRepository(
      const Session(id: 'u-founder', role: UserRole.founder),
      store: store,
    );

    final request = await administrator.execute(
      'organization/admin',
      const Command(
        'department',
        {'id': 'd-product', 'name': '产品与体验部', 'reason': '组织调整'},
        version: 1,
        idempotencyKey: 'org-change-1',
      ),
    );

    expect(request.fields['reviewState'], '待审');
    expect(request.fields['approvalMode'], 'DIRECT_MANAGER');
    expect(request.fields['reviewerId'], 'u-founder');
    expect(request.fields['reviewerConfigured'], isTrue);
    expect(
      (await founder.list('notifications', const Query())).items.any(
        (item) => item.fields['targetId'] == request.id,
      ),
      isTrue,
    );
    expect(
      (await administrator.execute(
        'organization/admin',
        const Command(
          'department',
          {'id': 'd-product', 'name': '产品与体验部', 'reason': '组织调整'},
          version: 1,
          idempotencyKey: 'org-change-1',
        ),
      )).id,
      request.id,
    );

    final approved = await founder.execute(
      'reviews',
      Command('approve', {'id': request.id}, version: request.version),
    );
    expect(approved.fields['reviewState'], '已通过');
    expect(approved.fields['step'], 1);
  });

  test('missing direct manager leaves organization change pending', () async {
    final repository = MockRepository(
      const Session(id: 'unmapped-admin', role: UserRole.admin),
      store: DemoStore(),
    );

    final request = await repository.execute(
      'organization/admin',
      const Command(
        'department',
        {'id': 'd-product', 'name': '产品与体验部', 'reason': '组织调整'},
        version: 1,
      ),
    );

    expect(request.fields['reviewState'], '待审');
    expect(request.fields['reviewerId'], isNull);
    expect(request.fields['reviewerConfigured'], isFalse);
  });

  test('founder authorized revision applies immediately with exemption record', () async {
    final store = DemoStore()
      ..records['dashboard/company'] = [
        const Record(
          id: 'focus-founder',
          title: '公司重点',
          ownerId: 'u-founder',
          version: 4,
          fields: {'body': '旧内容'},
        ),
      ];
    final founder = MockRepository(
      const Session(id: 'u-founder', role: UserRole.founder),
      store: store,
    );

    final result = await founder.execute(
      'dashboard/company',
      const Command(
        'request-review',
        {'id': 'focus-founder', '内容': '新内容', '修改理由': '年度目标调整'},
        version: 4,
      ),
    );

    expect(result.fields['reviewState'], '已通过');
    expect(result.fields['decisionSource'], 'FOUNDER_EXEMPT');
    expect((await founder.detail('dashboard/company', 'focus-founder')).fields['body'], '新内容');
    expect((await founder.list('reviews', const Query())).items.first.id, result.id);
  });

  test('review decision rejects stale, self, unassigned, and reasonless actions', () async {
    final store = DemoStore()
      ..records['reviews'] = [
        const Record(
          id: 'assigned',
          title: '已分配申请',
          ownerId: 'u2',
          version: 3,
          fields: {
            'reviewState': '待审',
            'reviewerId': 'u1',
            'baseVersion': 1,
          },
        ),
        const Record(
          id: 'unassigned',
          title: '未分配申请',
          ownerId: 'u2',
          fields: {'reviewState': '待审', 'reviewerId': null},
        ),
        const Record(
          id: 'self',
          title: '本人申请',
          ownerId: 'u1',
          version: 1,
          fields: {'reviewState': '待审', 'reviewerId': 'u1'},
        ),
      ];
    final manager = MockRepository(const Session(id: 'u1'), store: store);
    final other = MockRepository(
      const Session(id: 'u-product-dir', role: UserRole.director),
      store: store,
    );

    for (final attempt in [
      () => manager.execute(
        'reviews',
        const Command('approve', {'id': 'assigned'}, version: 2),
      ),
      () => manager.execute(
        'reviews',
        const Command('approve', {'id': 'unassigned'}, version: 1),
      ),
      () => manager.execute(
        'reviews',
        const Command('approve', {'id': 'self'}, version: 1),
      ),
      () => other.execute(
        'reviews',
        const Command('approve', {'id': 'assigned'}, version: 3),
      ),
      () => manager.execute(
        'reviews',
        const Command('reject', {'id': 'assigned'}, version: 3),
      ),
    ]) {
      await expectLater(attempt(), throwsA(isA<ApiFailure>()));
    }

    final rejected = await manager.execute(
      'reviews',
      const Command(
        'reject',
        {'id': 'assigned', 'reason': '缺少必要说明'},
        version: 3,
      ),
    );
    expect(rejected.fields['reviewState'], '已驳回');
  });
}
