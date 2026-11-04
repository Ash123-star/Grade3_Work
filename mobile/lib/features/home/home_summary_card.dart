import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/providers.dart';
import '../../data/models/models.dart';
import '../../shared/generated_assets.dart';
import '../../theme/app_theme.dart';

class HomeSummaryCard extends ConsumerWidget {
  const HomeSummaryCard({
    super.key,
    required this.title,
    required this.resource,
    required this.icon,
    required this.onAll,
    required this.onItem,
  });
  final String title, resource, icon;
  final VoidCallback onAll;
  final ValueChanged<Record> onItem;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homePreviewProvider(resource));
    final colors = Theme.of(context).colorScheme;
    final tokens =
        Theme.of(context).extension<PaperLayoutTokens>() ??
        const PaperLayoutTokens();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: resource == 'dashboard/company'
            ? SunnyPalette.blue
            : SunnyPalette.primaryContainer,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(tokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TuantuanIcon(icon, size: 28),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            state.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Column(
                children: [
                  const Text('暂时无法加载'),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(homePreviewProvider(resource)),
                    child: const Text('重试'),
                  ),
                ],
              ),
              data: (page) => page.items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text('暂无记录'),
                    )
                  : Column(
                      children: [
                        for (final item in page.items.take(2))
                          InkWell(
                            onTap: () => onItem(item),
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            TextButton(
              onPressed: onAll,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('查看全部'), Icon(Icons.north_east, size: 16)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
