import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/identity_card.dart';

void main() {
  test('mock profile derives age, masks ID and rejects age writes', () async {
    final repo = MockRepository(const Session());
    final profile = await repo.detail('organization/profile', 'u1');
    expect(profile.fields['age'], isNull);
    final saved = await repo.execute(
      'organization/profile',
      Command('update', {
        'id': 'u1',
        'idCardNumber': '11010519491231002x',
      }, version: profile.version),
    );
    expect(saved.fields['age'], identityCardAge('11010519491231002X'));
    expect(saved.fields.containsKey('idCardNumber'), isFalse);
    final read = await repo.detail('organization/profile', 'u1');
    expect(read.fields['idCardMasked'], '110***********002X');
    for (final invalid in [null, '', 110105198507160732]) {
      await expectLater(
        repo.execute(
          'organization/profile',
          Command('update', {
            'id': 'u1',
            'idCardNumber': invalid,
          }, version: read.version),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.validation,
          ),
        ),
      );
      expect(
        (await repo.detail('organization/profile', 'u1')).version,
        read.version,
      );
    }

    await expectLater(
      repo.execute(
        'organization/profile',
        Command('update', {'id': 'u1', 'age': 18}, version: read.version),
      ),
      throwsA(anything),
    );
  });

  test('valid checksum and birthday boundary', () {
    expect(
      identityCardError('11010519491231002x', now: DateTime.utc(2026, 12, 30)),
      isNull,
    );
    expect(
      identityCardAge(
        '11010519491231002X',
        now: DateTime.utc(2026, 12, 30, 15),
      ),
      76,
    );
    expect(
      identityCardAge(
        '11010519491231002X',
        now: DateTime.utc(2026, 12, 30, 16),
      ),
      77,
    );
  });
  test('reject malformed date and checksum', () {
    for (final value in [
      '',
      '123',
      '110105194912310021',
      '11010519900230002X',
    ]) {
      expect(identityCardError(value), isNotNull);
      expect(identityCardAge(value), isNull);
    }
  });
}
