import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'sunny_widgets.dart';
import 'paper_layout.dart';

class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration({
    super.key,
    this.title = '这里还没有记录',
    this.subtitle = '新的安排会出现在这里',
    this.action,
    this.showCharacter = true,
  });
  final String title, subtitle;
  final Widget? action;
  final bool showCharacter;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: !showCharacter
              ? const Icon(Icons.lock_outline, size: 40)
              : const WorkBuddy(size: 56, pose: BuddyPose.empty),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        ?action,
      ],
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel(this.message, {super.key, this.retry});
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => PaperSurface(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
        if (retry != null)
          TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
      ],
    ),
  );
}

/// Uses the existing typed errors; access failures never expose stale content.
class RecordFailure extends StatelessWidget {
  const RecordFailure(this.error, {super.key, this.retry});
  final Object error;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) {
    final kind = error is ApiFailure
        ? (error as ApiFailure).kind
        : FailureKind.server;
    final title = switch (kind) {
      FailureKind.forbidden => '无权访问',
      FailureKind.unauthorized => '登录已失效',
      FailureKind.notFound => '内容不可用',
      FailureKind.timeout || FailureKind.unavailable => '暂时无法连接',
      FailureKind.conflict => '内容已有新版本',
      _ => '加载未完成',
    };
    return PaperSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (kind == FailureKind.timeout || kind == FailureKind.unavailable)
            const Center(child: WorkBuddy(size: 56, pose: BuddyPose.retry)),
          const SizedBox(height: 12),
          Text('$error'),
          const SizedBox(height: 16),
          if (retry != null &&
              ![
                FailureKind.forbidden,
                FailureKind.unauthorized,
                FailureKind.notFound,
              ].contains(kind))
            OutlinedButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          TextButton(
            onPressed: () {
              if (kind == FailureKind.unauthorized) {
                context.go('/auth/login');
              } else if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
            child: Text(kind == FailureKind.unauthorized ? '重新登录' : '安全返回'),
          ),
        ],
      ),
    );
  }
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PaperSurface(
                child: SizedBox(
                  height: 40,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 160,
                      height: 10,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
