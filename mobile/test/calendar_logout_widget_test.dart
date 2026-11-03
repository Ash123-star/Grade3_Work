import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/local/calendar_command_store.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'support/local_test_state.dart';

class CleanupCommandStore extends CalendarCommandStore {
  CleanupCommandStore(super.drafts);
  final entered = Completer<void>();
  Completer<void>? barrier;
  bool fail = true;
  @override
  Future<void> clear(Session session) async {
    entered.complete();
    if (barrier != null) await barrier!.future;
    if (fail) throw StateError('injected cleanup failure');
    await super.clear(session);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final changeAccount in [false, true]) {
    testWidgets(
      'calendar cleanup failure preserves logout and new session: $changeAccount',
      (tester) async {
        late CleanupCommandStore store;
        final container = testContainer(
          overrides: [
            calendarCommandStoreProvider.overrideWith(
              (ref) =>
                  store = CleanupCommandStore(ref.read(draftStoreProvider)),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(calendarCommandStoreProvider);
        if (changeAccount) store.barrier = Completer<void>();
        var finished = false;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  onPressed: () async {
                    await logoutCurrentSession(ref);
                    finished = true;
                  },
                  child: const Text('退出'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('退出'));
        await tester.pump();
        expect(store.entered.isCompleted, isTrue);
        if (changeAccount) {
          container.read(sessionProvider.notifier).state = const Session(
            id: 'B',
            token: 'new-session',
          );
          container.read(sessionEpochProvider);
          store.barrier!.complete();
        }
        await settleLocalIo(tester);
        expect(finished, isTrue);
        final session = container.read(sessionProvider);
        if (changeAccount) {
          expect(session.id, 'B');
          expect(session.canReadBusiness, isTrue);
        } else {
          expect(session.canReadBusiness, isFalse);
          expect(container.read(sessionStorageErrorProvider), contains('清理失败'));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
