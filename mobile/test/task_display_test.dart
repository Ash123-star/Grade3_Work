import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/task_display.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';

void main() {
  test('known tags stay Chinese and unknown tags do not expose IDs', () {
    expect(taskTagLabel({'tagId': 'department-research'}), '研发');
    expect(taskTagLabel({'tag_id': 'department-design'}), '设计');
    expect(taskTagLabel({'tagId': 'custom', 'tagName': '客户回访'}), '客户回访');
    expect(taskTagLabel({'tagId': 'custom'}), '标签名称未提供');
  });

  test(
    'participant names preserve ID order, duplicate names and missing data',
    () {
      expect(
        taskParticipantNames(
          {
            'participantIds': ['u2', 'u1', 'unknown'],
            'participantNames': ['u2', 'u1', 'unknown'],
          },
          namesById: {'u1': '林小满', 'u2': '陈一诺'},
        ),
        ['陈一诺', '林小满', '成员姓名未提供'],
      );
      expect(
        taskParticipantNames({
          'participant_ids': ['a', 'b'],
          'participant_names': ['王晨', '王晨'],
        }),
        ['王晨', '王晨'],
      );
    },
  );

  test(
    'new mock dispatch returns Chinese tag and exact demo names on reread',
    () async {
      final repo = MockRepository(const Session(), store: DemoStore());
      final created = await repo.execute(
        'tasks',
        const Command('create', {
          'title': '十月需求评审准备',
          '任务内容': '整理评审问题并与产品同事确认排期',
          'tagId': 'department-research',
          'participantIds': ['u2', 'u1'],
        }),
      );
      expect(created.fields['tagName'], '研发');
      expect(created.fields['participantNames'], ['陈一诺', '林小满']);
      final reread = await repo.detail('tasks', created.id);
      expect(reread.fields['participantNames'], ['陈一诺', '林小满']);
      expect(reread.fields['participantIds'], ['u2', 'u1']);
      expect(reread.version, created.version);
    },
  );
}
