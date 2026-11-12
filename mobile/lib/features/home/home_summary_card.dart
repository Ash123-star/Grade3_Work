import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/providers.dart';
import '../../data/models/models.dart';
import '../../shared/generated_assets.dart';
import '../../theme/home_paper_theme.dart';

class HomeSummaryCard extends ConsumerWidget {
  const HomeSummaryCard({
    super.key,
    required this.title,
    required this.resource,
    required this.onAll,
    required this.onItem,
  });
  final String title, resource;
  final VoidCallback onAll;
  final ValueChanged<Record> onItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homePreviewProvider(resource));
    final paper = HomePaperTokens.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 375;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: HomePaperTokens.noteShadow, offset: Offset(0, 3)),
        ],
      ),
      child: Material(
        color: resource == 'dashboard/company' ? paper.note : paper.surface,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: HomePaperTokens.noteEdge),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: const _LetterPaperPainter(),
          child: InkWell(
            onTap: onAll,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: narrow ? 10 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: large ? 56 : 48),
                    child: Row(
                      children: [
                        TuantuanIcon(
                          resource == 'dashboard/company' ? 'calendar' : 'task',
                          size: narrow ? 22 : 24,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: paper.heading(narrow ? 15 : 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  state.when(
                    loading: () => const SizedBox(
                      height: 96,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (e, _) => ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 96),
                      child: TextButton(
                        onPressed: () =>
                            ref.invalidate(homePreviewProvider(resource)),
                        style: TextButton.styleFrom(
                          foregroundColor: HomePaperTokens.error,
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('加载失败，重试'),
                      ),
                    ),
                    data: (page) => page.items.isEmpty
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 96),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                resource == 'dashboard/company'
                                    ? '暂无公司事项'
                                    : '暂无参与任务',
                                style: paper.body(13, color: paper.muted),
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (
                                var i = 0;
                                i <
                                    page.items
                                        .take(
                                          resource == 'tasks/received-card'
                                              ? 3
                                              : 2,
                                        )
                                        .length;
                                i++
                              ) ...[
                                if (i > 0)
                                  const Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: HomePaperTokens.previewLine,
                                  ),
                                InkWell(
                                  onTap: () => onItem(page.items[i]),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 5,
                                        ),
                                        child: Text(
                                          page.items[i].title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: paper.body(15, height: 1.55),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                  TextButton(
                    onPressed: onAll,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: HomePaperTokens.moreInk,
                      textStyle: paper.body(narrow ? 10 : 11),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('查看全部'),
                        Icon(Icons.chevron_right, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet stationery details painted locally; no bitmap texture obscures text.
class _LetterPaperPainter extends CustomPainter {
  const _LetterPaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      ..color = HomePaperTokens.noteRule
      ..strokeWidth = .6;
    for (var y = 56.0; y < size.height - 42; y += 24) {
      canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), rule);
    }
    final fold = Path()
      ..moveTo(size.width - 17, 0)
      ..lineTo(size.width - 17, 17)
      ..lineTo(size.width, 17)
      ..close();
    canvas.drawPath(fold, Paint()..color = HomePaperTokens.noteFold);
    canvas.drawLine(Offset(size.width - 17, 17), Offset(size.width, 17), rule);
  }

  @override
  bool shouldRepaint(covariant _LetterPaperPainter oldDelegate) => false;
}
