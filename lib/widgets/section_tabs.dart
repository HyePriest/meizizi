import 'package:flutter/material.dart';

import 'desktop_layout.dart';

class SectionTabs extends StatelessWidget {
  const SectionTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  static Widget _slot(Widget child) =>
      isDesktop ? SizedBox(width: 120, child: child) : Expanded(child: child);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: .45),
            ),
          ),
        ),
        child: Row(
          // Desktop: keep the tabs together in the middle instead of
          // spreading them across the whole window.
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < labels.length; i++)
              _slot(
                Semantics(
                  selected: selected == i,
                  button: true,
                  child: InkWell(
                    onTap: () => onSelected(i),
                    child: SizedBox(
                      height: 42,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Center(
                              child: Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: selected == i
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: selected == i
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            height: 3,
                            width: 24,
                            decoration: BoxDecoration(
                              color: selected == i
                                  ? colors.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
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
}
