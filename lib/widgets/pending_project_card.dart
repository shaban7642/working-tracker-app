import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../models/pending_time_entry.dart';
import '../models/report_task.dart';
import '../providers/project_tasks_provider.dart';
import '../services/api_service.dart';
import 'pending_task_item.dart';
import 'add_task_dialog.dart';

/// Expandable card for a pending time entry in the pending tasks dialog.
/// Shows project info, duration, and allows adding tasks.
class PendingProjectCard extends ConsumerStatefulWidget {
  final PendingTimeEntry entry;
  final bool initiallyExpanded;
  final bool hasTasksAdded;
  final VoidCallback onAddTask;
  final Function(ReportTask task)? onTaskAdded;

  const PendingProjectCard({
    super.key,
    required this.entry,
    this.initiallyExpanded = false,
    this.hasTasksAdded = false,
    required this.onAddTask,
    this.onTaskAdded,
  });

  @override
  ConsumerState<PendingProjectCard> createState() => _PendingProjectCardState();
}

class _PendingProjectCardState extends ConsumerState<PendingProjectCard>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  // Colors
  static const _greenColor = Color(0xFF22C55E);
  static const _blueColor = Color(0xFF3B82F6);

  /// Get the provider key for this entry (projectId + date)
  ProjectTasksKey get _tasksKey => ProjectTasksKey(
        projectId: widget.entry.projectId,
        date: widget.entry.dateForApi,
      );

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    if (_isExpanded) {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  /// Edit an existing task using the AddTaskSheet
  Future<void> _editTask(ReportTask task) async {
    // Check if task has a reportId
    if (task.reportId == null || task.reportId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cannot edit task: missing report ID'),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    // Show edit sheet using the same form as add task
    final result = await AddTaskSheet.showEdit(
      context: context,
      projectId: widget.entry.projectId,
      projectName: widget.entry.projectName,
      taskToEdit: task,
      onTaskUpdated: (updatedTask) {
        // Update local state with new task data
        ref.read(projectTasksProvider(_tasksKey).notifier).updateTask(updatedTask);
      },
    );

    if (result == true && mounted) {
      // Don't refresh - local state is already updated via onTaskUpdated callback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Task updated'),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  /// Delete a task
  Future<void> _deleteTask(ReportTask task) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Task',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "${task.taskName}"?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete from API - requires both reportId and taskId
      final api = ApiService();
      if (task.reportId == null || task.reportId!.isEmpty) {
        throw Exception('Task has no associated report ID');
      }
      final success = await api.deleteTask(task.reportId!, task.id);

      if (success) {
        // Remove from local state (don't refresh - keeps UI stable)
        ref.read(projectTasksProvider(_tasksKey).notifier).removeTask(task.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Task deleted'),
              backgroundColor: const Color(0xFF22C55E),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      } else {
        throw Exception('Failed to delete task');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete task: $e'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasksState = ref.watch(projectTasksProvider(_tasksKey));
    final hasTasks = widget.hasTasksAdded ||
        (tasksState is ProjectTasksLoaded && tasksState.hasTasks);
    final taskCount =
        tasksState is ProjectTasksLoaded ? tasksState.taskCount : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header - Always visible
          _buildHeader(hasTasks, taskCount),

          // Expanded Content - only build when expanded to prevent unnecessary API calls
          if (_isExpanded || _animationController.value > 0)
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: _buildExpandedContent(tasksState, taskCount),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool hasTasks, int taskCount) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: _toggleExpanded,
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(16),
          bottom: _isExpanded ? Radius.zero : const Radius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Project Avatar - Large square with letter
              _buildProjectAvatar(),
              const SizedBox(width: 16),

              // Project Name and Duration row
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Project Name - uppercase bold
                    Text(
                      widget.entry.projectName.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Duration with clock icon + task count badge
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.entry.formattedDuration,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Task count badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _greenColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 12,
                                color: _greenColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$taskCount',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _greenColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Circular chevron button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.elevatedSurfaceColor,
                  shape: BoxShape.circle,
                ),
                child: AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: AppTheme.textSecondary,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectAvatar() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: widget.entry.projectImage == null
            ? const LinearGradient(
                colors: [_blueColor, Color(0xFF1D4ED8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.entry.projectImage != null
          ? Image.network(
              widget.entry.projectImage!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildAvatarFallback();
              },
            )
          : _buildAvatarFallback(),
    );
  }

  Widget _buildAvatarFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_blueColor, Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          widget.entry.projectName.isNotEmpty
              ? widget.entry.projectName[0].toUpperCase()
              : 'P',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(ProjectTasksState tasksState, int taskCount) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.borderColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tasks header row with count badge and Add Task button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Tasks label with count badge
                Row(
                  children: [
                    const Text(
                      'Tasks',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _greenColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$taskCount',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _greenColor,
                        ),
                      ),
                    ),
                  ],
                ),
                // Add Task button
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: InkWell(
                    onTap: widget.onAddTask,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppTheme.borderColor,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Add Task',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tasks section
            _buildTasksSection(tasksState),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksSection(ProjectTasksState tasksState) {
    if (tasksState is ProjectTasksLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primaryColor,
            ),
          ),
        ),
      );
    }

    if (tasksState is ProjectTasksError) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.errorColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 16,
              color: AppTheme.errorColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Failed to load tasks',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.errorColor,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                ref
                    .read(projectTasksProvider(_tasksKey).notifier)
                    .loadTasks();
              },
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (tasksState is ProjectTasksLoaded && tasksState.tasks.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: tasksState.tasks.map((task) => PendingTaskItem(
          task: task,
          onEdit: () => _editTask(task),
          onDelete: () => _deleteTask(task),
        )).toList(),
      );
    }

    // Empty state
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No tasks added yet. Please add at least one task.',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFFF59E0B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
