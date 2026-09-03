import 'package:flutter/material.dart';

import '../theme.dart';

/// 태그 선택 + 새 태그 생성 위젯
class TagSelector extends StatelessWidget {
  final List<String> allTags;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final ValueChanged<String> onCreateTag;

  const TagSelector({
    super.key,
    required this.allTags,
    required this.selected,
    required this.onChanged,
    required this.onCreateTag,
  });

  Future<void> _showCreateDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 태그 만들기'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '태그 이름 (예: Biology, 논문A)'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('만들기')),
        ],
      ),
    );
    final tag = result?.trim() ?? '';
    if (tag.isNotEmpty) {
      onCreateTag(tag);
      final next = Set<String>.from(selected)..add(tag);
      onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...allTags.map((tag) {
          final isSelected = selected.contains(tag);
          return FilterChip(
            label: Text(tag),
            selected: isSelected,
            selectedColor: AppTheme.lightTeal,
            checkmarkColor: AppTheme.deepIndigo,
            onSelected: (v) {
              final next = Set<String>.from(selected);
              if (v) {
                next.add(tag);
              } else {
                next.remove(tag);
              }
              onChanged(next);
            },
          );
        }),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18, color: AppTheme.teal),
          label: const Text('새 태그'),
          onPressed: () => _showCreateDialog(context),
        ),
      ],
    );
  }
}
