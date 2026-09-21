import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models.dart';
import '../data/mock_repository.dart';
import '../data/repository.dart';
import 'config.dart';

final sessionProvider = StateProvider<Session>(
  (ref) => AppConfig.mock
      ? const Session()
      : const Session(active: false, role: UserRole.employee, dispatch: false),
);
final scenarioProvider = StateProvider<DemoScenario>(
  (ref) => DemoScenario.normal,
);
final fontScaleProvider = StateProvider<double>((ref) => 1);
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());
final periodProvider = StateProvider<String>((ref) => '日');
final repositoryProvider = Provider<Repository>((ref) {
  final session = ref.watch(sessionProvider);
  return AppConfig.mock
      ? MockRepository(session, scenario: ref.watch(scenarioProvider))
      : HttpRepository(AppConfig.baseUrl, session.token);
});
final recordsProvider = FutureProvider.autoDispose.family<PageResult, String>(
  (ref, resource) =>
      ref.watch(repositoryProvider).list(resource, const Query()),
);
final itemProvider = FutureProvider.autoDispose
    .family<Record, (String, String)>(
      (ref, key) => ref.watch(repositoryProvider).detail(key.$1, key.$2),
    );
final datedRecordsProvider = FutureProvider.autoDispose
    .family<PageResult, String>((ref, resource) {
      final range = BusinessRange(
        ref.watch(selectedDateProvider),
        ref.watch(periodProvider),
      );
      return ref
          .watch(repositoryProvider)
          .list(resource, Query(from: range.from, to: range.to));
    });
