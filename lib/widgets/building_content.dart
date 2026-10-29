import 'package:flutter/material.dart';

import '../data/models.dart';

/// Long floors retain normal paragraph reading in a separate, scrollable sheet.
class BuildingContent extends StatelessWidget {
  const BuildingContent({
    super.key,
    required this.enabled,
    required this.parts,
    required this.child,
  });
  final bool enabled;
  final List<Json> parts;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final text = parts.map((p) => '${p['text'] ?? ''}').join();
    final mediaCount = parts.where((p) => [3, 20].contains(number(p['type']))).length;
    if (!enabled || (text.length < 600 && mediaCount < 4)) return child;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, maxLines: 5, overflow: TextOverflow.ellipsis),
          TextButton.icon(
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('从头阅读本层全文'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (context) => SizedBox(
                height: MediaQuery.sizeOf(context).height * .85,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 20),
                        const Expanded(child: Text('本层全文 · 从上向下阅读')),
                        IconButton(
                          tooltip: '返回楼层',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
