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
final demoStoreProvider = Provider<DemoStore>((ref) => DemoStore());
final repositoryProvider = Provider<Repository>((ref) {
  final session = ref.watch(sessionProvider);
  return AppConfig.mock
      ? MockRepository(
          session,
          scenario: ref.watch(scenarioProvider),
          store: ref.watch(demoStoreProvider),
        )
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

void refreshBusiness(WidgetRef ref) {
  ref.invalidate(recordsProvider);
  ref.invalidate(datedRecordsProvider);
  ref.invalidate(itemProvider);
  ref.invalidate(memberRecordsProvider);
  ref.invalidate(logDayRecordsProvider);
}

final memberRecordsProvider = FutureProvider.autoDispose
    .family<PageResult, (String, String)>(
      (ref, key) =>
          ref.watch(repositoryProvider).list(key.$1, Query(ownerId: key.$2)),
    );

final logDateProvider=StateProvider<DateTime>((ref)=>DateTime.now());
final logDayRecordsProvider=FutureProvider.autoDispose.family<PageResult,(String,String?)>((ref,key){
  final date=ref.watch(logFilterDateProvider);
  final range=date==null?null:BusinessRange(date,'日');
  return ref.watch(repositoryProvider).list(key.$1,Query(ownerId:key.$2,from:range?.from,to:range?.to));
});

final logFilterDateProvider=StateProvider<DateTime?>((ref)=>null);
