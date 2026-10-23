import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors/api_failure.dart';
import '../core/state/providers.dart';
import '../data/models/models.dart';
import 'widgets.dart';

/// A confirmed page-local receipt is not a fetched company-wide reading list.
class DiaryReadReceipt extends ConsumerStatefulWidget {
  const DiaryReadReceipt(this.diary, {super.key, required this.onAccessDenied});
  final Record diary;
  final ValueChanged<ApiFailure> onAccessDenied;
  @override
  ConsumerState<DiaryReadReceipt> createState() => _DiaryReadReceiptState();
}

class _DiaryReadReceiptState extends ConsumerState<DiaryReadReceipt> {
  late final Session identity = ref.read(sessionProvider);
  bool busy = false, acknowledged = false;
  Object? error;
  bool get active {
    if (!mounted) return false;
    final current = ref.read(sessionProvider);
    return current.id == identity.id &&
        current.token == identity.token &&
        current.canReadBusiness;
  }

  Future<void> recordRead() async {
    if (!active || busy || acknowledged || !isSubmittedDiary(widget.diary)) {
      return;
    }
    final id = widget.diary.id;
    final repository = ref.read(repositoryProvider);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repository.execute('logs', Command('read', {'id': id}));
      if (active) setState(() => acknowledged = true);
    } catch (failure) {
      if (!active) return;
      if (failure is ApiFailure &&
          [
            FailureKind.forbidden,
            FailureKind.unauthorized,
          ].contains(failure.kind)) {
        widget.onAccessDenied(failure);
      } else {
        setState(() => error = failure);
      }
    } finally {
      if (active) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionProvider);
    if (!active || !isSubmittedDiary(widget.diary)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          acknowledged ? '本次阅读已登记' : '阅读登记',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          acknowledged
              ? '服务器已确认本次登记；这不代表其他人员的阅读情况。'
              : '阅读后可登记已读。登记不会修改正文，也不会通过审批或发送评语。',
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          ErrorPanel('阅读登记未完成：$error。可以再次记录，正文保持不变。'),
        ],
        if (!acknowledged)
          OutlinedButton.icon(
            onPressed: busy ? null : recordRead,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: SunnyLoadingIndicator(size: 18),
                  )
                : const Icon(Icons.done_all),
            label: Text(busy ? '正在记录…' : '记录已读'),
          ),
      ],
    );
  }
}

/// Absence of a query contract must never be represented as an empty result.
class DiaryReadingHistory extends StatelessWidget {
  const DiaryReadingHistory(this.diary, {super.key});
  final Record diary;
  @override
  Widget build(BuildContext context) {
    final value = diary.fields['readBy'];
    if (!diary.fields.containsKey('readBy') || value == null) {
      return const Text('服务暂未提供阅读人员清单，不能据此判断是否已读。');
    }
    if (value is String && value.trim().isEmpty ||
        value is List && value.isEmpty) {
      return const Text('暂无阅读记录');
    }
    if (value is String) return Text(value);
    return const Text('阅读人员清单格式未确认，请稍后重新读取。');
  }
}
