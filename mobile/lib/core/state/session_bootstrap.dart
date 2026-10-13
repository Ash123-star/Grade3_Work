import 'package:pandora_mobile/shared/sunny_button.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/session_store.dart';
import '../../data/local/secure_values.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repository.dart';
import '../../shared/sunny_widgets.dart';
import '../../theme/app_theme.dart';
import '../config.dart';
import '../errors/api_failure.dart';
import 'local_state.dart';
import 'providers.dart';

const emptySession = Session(
  id: '',
  name: '',
  active: false,
  dispatch: false,
  role: UserRole.employee,
);

/// Existing /auth/me is authoritative; persisted credentials grant no role.
Future<Session> recoverSession(
  SessionStore store,
  Future<Record> Function(StoredCredential) readIdentity,
) async {
  final credential = await store.read();
  if (credential == null) return emptySession;
  try {
    final user = await readIdentity(credential);
    final next = Session.fromRecord(
      user,
      token: credential.token,
      expiresAt: credential.expiresAt,
    );
    if (next.id != credential.account ||
        !credential.expiresAt.isAfter(DateTime.now()) ||
        !['ACTIVE', 'PENDING', 'DISABLED'].contains(next.status)) {
      await store.clear(token: credential.token);
      return emptySession;
    }
    if (next.status == 'DISABLED') {
      await store.clear(token: credential.token);
      return Session(
        id: next.id,
        name: next.name,
        status: 'DISABLED',
        active: false,
        dispatch: false,
        role: UserRole.employee,
      );
    }
    return next;
  } on ApiFailure catch (failure) {
    if (failure.kind == FailureKind.unauthorized ||
        failure.kind == FailureKind.forbidden) {
      await store.clear(token: credential.token);
      return emptySession;
    }
    rethrow;
  }
}

final recoveryIdentityProvider =
    Provider<Future<Record> Function(StoredCredential)>(
      (ref) => (credential) async {
        final repository = HttpRepository(
          AppConfig.baseUrl,
          credential.token,
          businessAllowed: false,
        );
        try {
          return await repository.detail('auth', 'me');
        } finally {
          repository.dio.close();
        }
      },
    );
final sessionRecoveryEnabledProvider = Provider<bool>(
  (ref) => !AppConfig.mock && !kIsWeb,
);

/// The router and business providers are not mounted before identity validation.
class SessionBootstrap extends ConsumerStatefulWidget {
  const SessionBootstrap({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SessionBootstrap> createState() => _SessionBootstrapState();
}

class _SessionBootstrapState extends ConsumerState<SessionBootstrap> {
  bool ready = false, working = true;
  String? error;
  @override
  void initState() {
    super.initState();
    if (!ref.read(sessionRecoveryEnabledProvider)) {
      ready = true;
      working = false;
    } else {
      unawaited(restore());
    }
  }

  Future<void> restore() async {
    final before = ref.read(sessionProvider);
    final store = ref.read(sessionStoreProvider);
    setState(() {
      working = true;
      error = null;
    });
    try {
      final session = await recoverSession(
        store,
        ref.read(recoveryIdentityProvider),
      );
      if (!mounted) {
        return;
      }
      final current = ref.read(sessionProvider);
      if (current.token != before.token || current.id != before.id) {
        setState(() {
          ready = true;
          working = false;
        });
        return;
      }
      ref.read(sessionProvider.notifier).state = session;
      ref.read(sessionStorageErrorProvider.notifier).state = null;
      setState(() {
        ready = true;
        working = false;
      });
    } catch (failure) {
      if (mounted) {
        final current = ref.read(sessionProvider);
        if (current.token != before.token || current.id != before.id) {
          setState(() {
            ready = true;
            working = false;
          });
          return;
        }
        setState(() {
          working = false;
          error = failure is LocalStorageFailure
              ? '$failure'
              : '暂时无法确认账号状态，请重试。';
        });
      }
    }
  }

  Future<void> clear() async {
    setState(() {
      working = true;
      error = null;
    });
    try {
      await ref.read(sessionStoreProvider).clear();
      if (!mounted) return;
      ref.read(sessionProvider.notifier).state = emptySession;
      setState(() {
        working = false;
        ready = true;
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          working = false;
          error = '$failure';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ready) return widget.child;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(ref.watch(fontScaleProvider))),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: WorkBuddy(
                        size: 76,
                        pose: error == null
                            ? BuddyPose.explaining
                            : BuddyPose.retry,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      working ? '正在恢复登录' : '暂时无法恢复登录',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    const Text('确认账号状态后进入工作台。本机加密草稿按账号保留。'),
                    const SizedBox(height: 24),
                    if (working) const LinearProgressIndicator(),
                    if (error != null) ...[
                      Text(error!),
                      const SizedBox(height: 16),
                      SunnyPrimaryButton(
                        onPressed: working ? null : restore,
                        child: const Text('重新验证登录'),
                      ),
                      OutlinedButton(
                        onPressed: working ? null : clear,
                        child: const Text('清除本机登录信息'),
                      ),
                      const Text('清除后需要重新登录；此操作不会删除草稿。'),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
