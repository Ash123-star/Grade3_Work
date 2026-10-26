import 'package:pandora_mobile/shared/sunny_button.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/shared/page_states.dart';
import 'providers.dart';
import 'local_state.dart';
import '../config.dart';
import 'live_notifications.dart';

/// Keeps the existing route/input mounted while foreground identity is checked.
class SessionLifecycle extends ConsumerStatefulWidget {
  const SessionLifecycle({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SessionLifecycle> createState() => _SessionLifecycleState();
}

class _SessionLifecycleState extends ConsumerState<SessionLifecycle>
    with WidgetsBindingObserver {
  Timer? expiry;
  bool backgrounded = false, exiting = false;
  String? exitError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleExpiry();
  }

  void scheduleExpiry() {
    expiry?.cancel();
    final session = ref.read(sessionProvider);
    if (session.token == null || session.expiresAt == null) {
      return;
    }
    final remaining = session.expiresAt!.difference(DateTime.now());
    expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!mounted) return;
      final current = ref.read(sessionProvider);
      if (current.token == session.token) {
        ref.read(sessionProvider.notifier).state = current.restrict(
          expired: true,
        );
        ref.read(sessionCheckProvider.notifier).state = null;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      backgrounded = true;
      ref.read(notificationForegroundProvider.notifier).state = false;
    } else if (state == AppLifecycleState.resumed && backgrounded) {
      backgrounded = false;
      if (ref.read(sessionProvider).token != null) {
        unawaited(validate());
      } else {
        ref.read(notificationForegroundProvider.notifier).state = true;
      }
    }
  }

  Future<void> validate() async {
    try {
      await refreshCurrentSession(ref, blockBusiness: true);
    } catch (_) {
      // The provider retains typed recovery; no credential/body logging.
    } finally {
      if (mounted) {
        ref.read(notificationForegroundProvider.notifier).state = true;
      }
    }
  }

  Future<void> exit() async {
    setState(() {
      exiting = true;
      exitError = null;
    });
    try {
      await logoutCurrentSession(ref);
    } catch (error) {
      if (mounted) setState(() => exitError = '$error');
    } finally {
      if (mounted) setState(() => exiting = false);
    }
  }

  @override
  void dispose() {
    expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(liveNotificationsProvider);
    ref.listen(sessionProvider, (previous, next) {
      scheduleExpiry();
      if (!next.authenticated ||
          previous?.token != next.token ||
          previous?.id != next.id) {
        ref.read(sessionCheckProvider.notifier).state = null;
      }
      if (!AppConfig.mock && previous?.token != null && next.token == null) {
        unawaited(clearCredential(previous!.token!));
      }
    });
    final check = ref.watch(sessionCheckProvider);
    final showCheck = check != null && ref.watch(sessionProvider).authenticated;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: showCheck, child: widget.child),
        if (check != null && showCheck)
          Scaffold(
            body: TuantuanPaperBackdrop(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: SunnyStatusIcon(
                              icon: check.hasError
                                  ? Icons.cloud_off_outlined
                                  : Icons.sync_rounded,
                              color: check.hasError
                                  ? Theme.of(context).colorScheme.error
                                  : const Color(0xFF4C8066),
                              size: 72,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            check.hasError ? '暂时无法确认登录状态' : '正在确认登录状态',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          const Text('确认账号状态后继续。本机草稿仍按原账号保留。'),
                          const SizedBox(height: 24),
                          if (check.isLoading)
                            const SunnyLoadingIndicator(size: 24),
                          if (check.hasError) ...[
                            Text(
                              '${check.error}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SunnyPrimaryButton(
                              onPressed: exiting ? null : validate,
                              child: const Text('重新验证登录'),
                            ),
                            OutlinedButton(
                              onPressed: exiting ? null : exit,
                              child: Text(exiting ? '正在退出…' : '退出登录'),
                            ),
                          ],
                          if (exitError != null)
                            Text(
                              exitError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> clearCredential(String token) async {
    try {
      await ref.read(sessionStoreProvider).clear(token: token);
    } catch (error) {
      if (mounted) {
        ref.read(sessionStorageErrorProvider.notifier).state = '$error';
      }
    }
  }
}
