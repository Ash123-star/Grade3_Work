import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/notification_display.dart';
import 'package:pandora_mobile/data/models/review_display.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';

void main() {
  DemoStore focusStore() => DemoStore()
    ..records['dashboard/company'] = [
      const Record(
        id: 'focus-founder',
        title: '公司重点',
        ownerId: 'u-founder',
        version: 4,
        fields: {'body': '旧内容'},
      ),
    ];

  test('founder revision routes to another founder instead of exemption', () async {
    final store = focusStore();
    final founder = MockRepository(
      const Session(id: 'u-founder', role: UserRole.founder),
      store: store,
    );
    final cofounder = MockRepository(
      const Session(id: 'u-cofounder', role: UserRole.founder),
      store: store,
    );

    final request = await founder.execute(
      'dashboard/company',
      const Command(
        'request-review',
        {'id': 'focus-founder', '内容': '新内容', '修改理由': '年度目标调整'},
        version: 4,
      ),
    );

    expect(request.fields['reviewState'], '待审');
    expect(request.fields['approvalMode'], 'FOUNDER_PEER');
    expect(request.fields['reviewerId'], 'u-cofounder');
    expect(request.fields['reviewerSelectable'], isTrue);
    expect(
      (await founder.detail('dashboard/company', 'focus-founder')).fields['body'],
      '旧内容',
    );

    await expectLater(
      founder.execute(
        'reviews',
        Command('approve', {'id': request.id}, version: request.version),
      ),
      throwsA(isA<ApiFailure>()),
    );

    final approved = await cofounder.execute(
      'reviews',
      Command('approve', {'id': request.id}, version: request.version),
    );
    expect(approved.fields['reviewState'], '已通过');
    expect(approved.fields['decisionSource'], 'FOUNDER_PEER');
    expect(approved.fields['reviewerSelectable'], isFalse);
  });

  test('applicant lists candidates and rejects invalid reviewer selection', () async {
    final store = focusStore();
    final founder = MockRepository(
      const Session(id: 'u-founder', role: UserRole.founder),
      store: store,
    );
    final request = await founder.execute(
      'dashboard/company',
      const Command(
        'request-review',
        {'id': 'focus-founder', '内容': '新内容', '修改理由': '调整'},
        version: 4,
      ),
    );

    final candidates = await founder.list(
      'reviews/reviewer-candidates',
      Query(ownerId: request.id),
    );
    expect(candidates.items.map((item) => item.id), ['u-cofounder']);
    expect(candidates.items.single.fields['current'], isTrue);

    for (final reviewer in ['u-founder', 'u-admin', 'missing']) {
      await expectLater(
        founder.execute(
          'reviews',
          Command(
            'select-reviewer',
            {'id': request.id, 'reviewerId': reviewer},
            version: request.version,
          ),
        ),
        throwsA(
          isA<ApiFailure>().having((e) => e.kind, 'kind', FailureKind.validation),
        ),
      );
    }

    final same = await founder.execute(
      'reviews',
      Command(
        'select-reviewer',
        {'id': request.id, 'reviewerId': 'u-cofounder'},
        version: request.version,
      ),
    );
    expect(same.fields['reviewerId'], 'u-cofounder');
  });

  test('reviewer selection is unsupported for direct manager requests', () async {
    final store = DemoStore()
      ..records['reviews'] = [
        const Record(
          id: 'direct',
          title: '直属申请',
          ownerId: 'u1',
          version: 1,
          fields: {
            'reviewState': '待审',
            'approvalMode': 'DIRECT_MANAGER',
            'reviewerId': 'u-product-dir',
          },
        ),
      ];
    final applicant = MockRepository(const Session(id: 'u1'), store: store);
    await expectLater(
      applicant.list('reviews/reviewer-candidates', const Query(ownerId: 'direct')),
      throwsA(isA<ApiFailure>().having((e) => e.kind, 'kind', FailureKind.conflict)),
    );
  });

  test('review mode labels and unassigned notification are localized', () {
    expect(reviewModeTitle('FOUNDER_PEER'), '创始人互审');
    expect(reviewModeTitle('ADMIN_MEMBERSHIP'), '管理员确认');
    expect(reviewModeTitle(null), '直属上级审核');
    expect(reviewUnassignedText('FOUNDER_PEER'), contains('其他在职创始人'));
    expect(notificationTitle('REVIEW_UNASSIGNED'), '有申请缺少审核人');
    expect(notificationResource('REVIEW_UNASSIGNED'), 'reviews');
  });
}
