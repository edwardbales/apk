import 'package:flutter/material.dart';

import '../theme.dart';

/// Which half of the Jobs view is showing (v1.25).
///
/// Active = still to print (Pending + Printing). Complete =
/// finished on this printer (Done + Forwarded) — a file lands
/// here the moment its printing is completely done.
enum JobSection { active, complete }

/// The Active / Complete switch at the top of the Jobs view.
///
/// Each side shows its count so the operator sees at a glance
/// how many jobs are still printing and how many are finished.
class JobSectionTabs extends StatelessWidget {
  const JobSectionTabs({
    super.key,
    required this.section,
    required this.activeCount,
    required this.completeCount,
    required this.onSectionChanged,
  });

  final JobSection section;
  final int activeCount;
  final int completeCount;
  final ValueChanged<JobSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(JobSection value, String label, int count) {
      final selected = section == value;
      return Expanded(
        child: TextButton(
          onPressed: selected ? null : () => onSectionChanged(value),
          style: TextButton.styleFrom(
            backgroundColor: selected
                ? SigntechTheme.brandBlue
                : Colors.transparent,
            foregroundColor:
                selected ? Colors.white : scheme.onSurface,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            '$label ($count)',
            style: TextStyle(
              fontWeight:
                  selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? Colors.white : scheme.onSurface,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          tab(JobSection.active, 'Active', activeCount),
          tab(JobSection.complete, 'Complete', completeCount),
        ],
      ),
    );
  }
}
