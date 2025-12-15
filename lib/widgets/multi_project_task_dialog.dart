import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../models/project_with_time.dart';
import '../providers/timer_provider.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import 'project_task_card.dart';
import 'gradient_button.dart';

/// Result from the multi-project task dialog
class MultiProjectTaskResult {
  final bool completed;
  final int totalTasksSubmitted;

  const MultiProjectTaskResult({
    this.completed = false,
    this.totalTasksSubmitted = 0,
  });

  bool get shouldProceed => completed;
}

/// Dialog mode
enum TaskDialogMode {
  /// Show all projects with time entries today (for checkout)
  checkout,
  /// Show only specific projects (for project switch)
  projectSwitch,
}

/// Dialog for submitting tasks for multiple projects
/// Shows expandable cards for each project with time entries
class MultiProjectTaskDialog extends ConsumerStatefulWidget {
  final String title;
  final TaskDialogMode mode;
  final List<ProjectWithTime>? initialProjects;

  const MultiProjectTaskDialog({
    super.key,
    this.title = 'Submit Tasks',
    this.mode = TaskDialogMode.checkout,
    this.initialProjects,
  });

  /// Show the dialog for checkout (all projects with time entries today)
  static Future<MultiProjectTaskResult?> showForCheckout({
    required BuildContext context,
  }) {
    return showDialog<MultiProjectTaskResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MultiProjectTaskDialog(
        title: 'Submit Tasks Before Checkout',
        mode: TaskDialogMode.checkout,
      ),
    );
  }

  /// Show the dialog for project switch (single project)
  static Future<MultiProjectTaskResult?> showForProjectSwitch({
    required BuildContext context,
    required ProjectWithTime project,
  }) {
    return showDialog<MultiProjectTaskResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MultiProjectTaskDialog(
        title: 'Submit Task Before Switching',
        mode: TaskDialogMode.projectSwitch,
        initialProjects: [project],
      ),
    );
  }

  @override
  ConsumerState<MultiProjectTaskDialog> createState() => _MultiProjectTaskDialogState();
}

class _MultiProjectTaskDialogState extends ConsumerState<MultiProjectTaskDialog> {
  final _logger = LoggerService();
  final _api = ApiService();

  List<ProjectWithTime> _projects = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    if (widget.initialProjects != null) {
      // Use provided projects (for project switch)
      setState(() {
        _projects = widget.initialProjects!;
        _isLoading = false;
      });
      return;
    }

    // Load all projects with time entries today (for checkout)
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final entries = await _api.getTodayTimeEntries();

      // Group entries by projectId
      final projectMap = <String, ProjectWithTime>{};

      for (final entry in entries) {
        final projectId = _extractProjectId(entry);
        final projectName = _extractProjectName(entry);
        final duration = _extractDuration(entry);

        if (projectId.isNotEmpty) {
          if (projectMap.containsKey(projectId)) {
            // Add to existing project's total time
            final existing = projectMap[projectId]!;
            projectMap[projectId] = existing.copyWith(
              totalTimeWorked: existing.totalTimeWorked + duration,
            );
          } else {
            // Create new project entry
            projectMap[projectId] = ProjectWithTime(
              projectId: projectId,
              projectName: projectName,
              totalTimeWorked: duration,
            );
          }
        }
      }

      // IMPORTANT: Also include the currently running timer's project
      // The API only returns CLOSED time entries, so the active timer won't be included
      final currentTimer = ref.read(currentTimerProvider);
      if (currentTimer != null) {
        final completedDurations = ref.read(completedProjectDurationsProvider);
        final completedTime = completedDurations[currentTimer.projectId] ?? Duration.zero;
        final totalTime = currentTimer.elapsedDuration + completedTime;

        if (projectMap.containsKey(currentTimer.projectId)) {
          // Add current timer's time to existing entry
          final existing = projectMap[currentTimer.projectId]!;
          projectMap[currentTimer.projectId] = existing.copyWith(
            totalTimeWorked: existing.totalTimeWorked + currentTimer.elapsedDuration,
          );
        } else {
          // Create new entry for active project
          projectMap[currentTimer.projectId] = ProjectWithTime(
            projectId: currentTimer.projectId,
            projectName: currentTimer.projectName,
            totalTimeWorked: totalTime,
          );
        }
        _logger.info('Added active timer project: ${currentTimer.projectName} with ${totalTime.inMinutes} minutes');
      }

      setState(() {
        _projects = projectMap.values.toList();
        _isLoading = false;
      });

      _logger.info('Loaded ${_projects.length} projects with time entries');

      // Only auto-close if:
      // 1. No projects with time entries
      // 2. This is NOT checkout mode (checkout should always show dialog even if empty)
      // For project start (when we use checkout mode but no timer), auto-close if empty
      if (_projects.isEmpty && widget.mode == TaskDialogMode.checkout && currentTimer == null) {
        // Close dialog and return null (no action needed)
        if (mounted) {
          Navigator.of(context).pop(null);
        }
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to load projects', e, stackTrace);
      setState(() {
        _error = 'Failed to load projects: $e';
        _isLoading = false;
      });
    }
  }

  String _extractProjectId(Map<String, dynamic> entry) {
    final project = entry['project'];
    if (project is Map) {
      return project['_id']?.toString() ?? project['id']?.toString() ?? '';
    }
    return entry['projectId']?.toString() ?? '';
  }

  String _extractProjectName(Map<String, dynamic> entry) {
    final project = entry['project'];
    if (project is Map) {
      return project['name']?.toString() ?? 'Unknown Project';
    }
    return entry['projectName']?.toString() ?? 'Unknown Project';
  }

  Duration _extractDuration(Map<String, dynamic> entry) {
    final duration = entry['duration'];
    if (duration is num) {
      return Duration(seconds: duration.toInt());
    }
    return Duration.zero;
  }

  void _onTaskSubmitted(int projectIndex, SubmittedTaskInfo task) {
    setState(() {
      _projects[projectIndex] = _projects[projectIndex].addTask(task);
    });
  }

  bool get _canProceed {
    // All projects must have at least one task
    return _projects.isNotEmpty && _projects.every((p) => p.hasTask);
  }

  int get _totalTasksSubmitted {
    return _projects.fold(0, (sum, p) => sum + p.taskCount);
  }

  int get _projectsWithTasks {
    return _projects.where((p) => p.hasTask).length;
  }

  void _onDone() {
    Navigator.of(context).pop(MultiProjectTaskResult(
      completed: true,
      totalTasksSubmitted: _totalTasksSubmitted,
    ));
  }

  void _onCancel() {
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(),

            // Content
            Flexible(
              child: _isLoading
                  ? _buildLoading()
                  : _error != null
                      ? _buildError()
                      : _projects.isEmpty
                          ? _buildEmpty()
                          : _buildProjectList(),
            ),

            // Footer
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.assignment_outlined,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (!_isLoading && _projects.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '$_projectsWithTasks/${_projects.length} projects have tasks',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading projects...'),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppTheme.errorColor,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.errorColor,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _loadProjects,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No projects with time entries today',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Each project must have at least one task submitted.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Project cards
          ...List.generate(_projects.length, (index) {
            return ProjectTaskCard(
              project: _projects[index],
              initiallyExpanded: _projects.length == 1 || !_projects[index].hasTask,
              onTaskSubmitted: (task) => _onTaskSubmitted(index, task),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          top: BorderSide(color: AppTheme.borderColor),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: [
          // Cancel button
          TextButton(
            onPressed: _onCancel,
            child: const Text('Cancel'),
          ),

          // Flexible spacer to push items to the right
          const Expanded(child: SizedBox()),

          // Status indicator
          if (!_isLoading && _projects.isNotEmpty) ...[
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _canProceed
                      ? AppTheme.successColor.withValues(alpha: 0.1)
                      : AppTheme.warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _canProceed ? Icons.check_circle : Icons.pending,
                      size: 14,
                      color: _canProceed ? AppTheme.successColor : AppTheme.warningColor,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$_totalTasksSubmitted task${_totalTasksSubmitted != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _canProceed ? AppTheme.successColor : AppTheme.warningColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Done button
          SizedBox(
            width: 90,
            child: GradientButton(
              onPressed: _canProceed ? _onDone : null,
              height: 40,
              child: const Text(
                'Done',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
