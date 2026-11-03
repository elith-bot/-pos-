import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Switches between page sections on compact screens without changing data filters.
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

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < labels.length; i++)
          ChoiceChip(
            label: Text(labels[i]),
            selected: i == selected,
            selectedColor: AppColors.primaryLight.withValues(alpha: .12),
            onSelected: (_) => onSelected(i),
          ),
      ],
    ),
  );
}
