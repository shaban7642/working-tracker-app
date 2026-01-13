import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../models/pending_time_entry.dart';
import '../models/report_task.dart';
import '../providers/pending_tasks_provider.dart';
import '../providers/project_tasks_provider.dart';
import 'pending_project_card.dart';
import 'add_task_dialog.dart';

/// Main dialog for pending tasks.
/// Shows all time entries that need tasks to be added.
/// Cannot be dismissed until all entries have at least one task.
class PendingTasksDialog extends ConsumerStatefulWidget {
  const PendingTasksDialog({super.key});

  /// Show the pending tasks dialog
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PendingTasksDialog(),
    );
  }

  @override
  ConsumerState<PendingTasksDialog> createState() => _PendingTasksDialogState();
}

class _PendingTasksDialogState extends ConsumerState<PendingTasksDialog> {
  // Track which entries have had tasks added in this session
  final Set<String> _completedEntryIds = {};

  /// Get the provider key for an entry
  ProjectTasksKey _getTasksKey(PendingTimeEntry entry) => ProjectTasksKey(
        projectId: entry.projectId,
        date: entry.dateForApi,
      );

  @override
  Widget build(BuildContext context) {
    final pendingState = ref.watch(pendingTasksProvider);
    final canSkip = ref.watch(canSkipPendingTasksProvider);

    return PopScope(
      canPop: _canDismiss(pendingState),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_canDismiss(pendingState)) {
          _showCannotDismissMessage();
        }
      },
      child: Dialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 850,
            minWidth: 600,
            maxHeight: 700,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              _buildHeader(pendingState),

              // Content
              Flexible(
                child: _buildContent(pendingState, canSkip),
              ),

              // Footer
              _buildFooter(pendingState, canSkip),
            ],
          ),
        ),
      ),
    );
  }

  bool _canDismiss(PendingTasksState state) {
    if (state is PendingTasksCompleted || state is PendingTasksSkipped) {
      return true;
    }
    if (state is PendingTasksLoaded) {
      return state.allEntriesCompleted ||
          _completedEntryIds.length >= state.entries.length;
    }
    return false;
  }

  void _showCannotDismissMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Please add tasks for all projects before continuing'),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildHeader(PendingTasksState state) {
    int remaining = 0;
    int total = 0;

    if (state is PendingTasksLoaded) {
      total = state.entries.length;
      remaining = total - _completedEntryIds.length;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.elevatedSurfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          // Warning icon in amber circle
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: const Color(0xFFF59E0B),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),

          // Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PENDING TASKS',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                if (total > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$remaining of $total remaining',
                    style: TextStyle(
                      fontSize: 13,
                      color: remaining > 0
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF22C55E),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(PendingTasksState state, bool canSkip) {
    if (state is PendingTasksLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primaryColor),
              SizedBox(height: 16),
              Text(
                'Loading pending tasks...',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state is PendingTasksError) {
      return _buildErrorContent(state, canSkip);
    }

    if (state is PendingTasksLoaded) {
      return _buildLoadedContent(state);
    }

    // Initial or completed state
    return const SizedBox.shrink();
  }

  Widget _buildErrorContent(PendingTasksError state, bool canSkip) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: AppTheme.errorColor,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load pending tasks',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.message,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Retry button
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(pendingTasksProvider.notifier).retry();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: const Color(0xFF121212),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
                // Skip button (only if retry count >= 3)
                if (canSkip) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () {
                      ref.read(pendingTasksProvider.notifier).skip();
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (canSkip) ...[
              const SizedBox(height: 8),
              Text(
                'You can try again next time you open the app',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedContent(PendingTasksLoaded state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: state.entries.map((entry) {
          return PendingProjectCard(
            entry: entry,
            hasTasksAdded: _completedEntryIds.contains(entry.id),
            onAddTask: () => _showAddTaskDialog(entry),
            onTaskAdded: (task) => _onTaskAdded(entry, task),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _showAddTaskDialog(PendingTimeEntry entry) async {
    final result = await AddTaskSheet.show(
      context: context,
      projectId: entry.projectId,
      projectName: entry.projectName,
      entryIds: entry.allEntryIds, // Pass all entry IDs for merged entries
      reportDate: entry.date,
      onTaskCreated: (taskData) {
        // Convert the task data to ReportTask and call _onTaskAdded
        final task = ReportTask.fromJson(taskData);
        _onTaskAdded(entry, task);
      },
    );

    // If task was added successfully (result == true), it's already handled by onTaskCreated
    if (result == true) {
      // Task was added - the callback already handled it
    }
  }

  void _onTaskAdded(PendingTimeEntry entry, ReportTask task) {
    // Mark entry as completed
    setState(() {
      _completedEntryIds.add(entry.id);
    });

    // Update provider state
    ref.read(pendingTasksProvider.notifier).markEntryCompleted(entry.id);

    // Add task to local state
    ref.read(projectTasksProvider(_getTasksKey(entry)).notifier).addTask(task);
  }

  Widget _buildFooter(PendingTasksState state, bool canSkip) {
    final allCompleted = state is PendingTasksLoaded &&
        (_completedEntryIds.length >= state.entries.length ||
            state.allEntriesCompleted);

    // Green color from screenshot
    const greenColor = Color(0xFF22C55E);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: allCompleted
              ? () {
                  ref.read(pendingTasksProvider.notifier).markAllCompleted();
                  Navigator.of(context).pop();
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: greenColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: greenColor.withValues(alpha: 0.4),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 20,
                color: allCompleted
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Text(
                allCompleted ? 'Continue' : 'Complete all tasks to continue',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
