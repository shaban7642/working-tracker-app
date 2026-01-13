import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/report_task.dart';

/// Widget to display a single task item in the pending tasks dialog.
/// Shows task name (bold/uppercase), description, and edit/delete icons.
class PendingTaskItem extends StatelessWidget {
  final ReportTask task;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const PendingTaskItem({
    super.key,
    required this.task,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.borderColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Task content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Task name - bold/uppercase
                Text(
                  task.taskName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
                if (task.taskDescription.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  // Task description
                  Text(
                    task.taskDescription,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Action buttons - always visible
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Edit button
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onEdit,
                  child: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Delete button
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppTheme.errorColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
