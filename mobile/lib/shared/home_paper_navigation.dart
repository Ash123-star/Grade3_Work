import 'package:flutter/material.dart';
import '../theme/home_paper_theme.dart';
import 'generated_assets.dart';

/// One shared five-tab bar, matching the approved home prototype on every tab.
class HomePaperNavigation extends StatelessWidget {
  const HomePaperNavigation({
    super.key,
    required this.index,
    required this.onSelected,
  });
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final paper = HomePaperTokens.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: HomePaperTokens.navigationSurface,
        border: Border(top: BorderSide(color: HomePaperTokens.navigationLine)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Stack(
            children: [
              NavigationBarTheme(
                data: NavigationBarThemeData(
                  labelTextStyle: WidgetStateProperty.resolveWith(
                    (states) => paper
                        .body(
                          10,
                          color: states.contains(WidgetState.selected)
                              ? HomePaperTokens.navigationInk
                              : paper.muted,
                        )
                        .copyWith(
                          fontWeight: states.contains(WidgetState.selected)
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                  ),
                ),
                child: NavigationBar(
                  backgroundColor: HomePaperTokens.navigationSurface,
                  surfaceTintColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  height: 73,
                  selectedIndex: index,
                  onDestinationSelected: onSelected,
                  animationDuration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  indicatorColor: Colors.transparent,
                  labelPadding: const EdgeInsets.only(top: 3, bottom: 4),
                  destinations: [
                    for (final tab in const [
                      ('首页', 'home'),
                      ('公司', 'calendar'),
                      ('日志', 'log'),
                      ('AI地图', 'ai'),
                      ('我的', 'members'),
                    ])
                      NavigationDestination(
                        label: tab.$1,
                        icon: SizedBox(
                          width: 46,
                          height: 32,
                          child: Center(child: TuantuanIcon(tab.$2, size: 25)),
                        ),
                        selectedIcon: DecoratedBox(
                          decoration: BoxDecoration(
                            color: HomePaperTokens.navigationTray,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: SizedBox(
                            width: 46,
                            height: 32,
                            child: Center(
                              child: TuantuanIcon(tab.$2, size: 25),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        for (var i = 0; i < 5; i++)
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                width: 4,
                                height: 4,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i == index
                                        ? HomePaperTokens.navigationDot
                                        : Colors.transparent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
