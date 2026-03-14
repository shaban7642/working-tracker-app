import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pending_time_entry.dart';
import '../services/graphql_api_service.dart';
import '../services/logger_service.dart';
import 'auth_provider.dart';

// ============================================================================
// PENDING TASKS STATE
// ============================================================================

/// Base class for pending tasks states
sealed class PendingTasksState {
  const PendingTasksState();
}

/// Initial state before any data is loaded
class PendingTasksInitial extends PendingTasksState {
  const PendingTasksInitial();
}

/// Loading state while fetching pending entries
class PendingTasksLoading extends PendingTasksState {
  const PendingTasksLoading();
}

/// Successfully loaded pending entries
class PendingTasksLoaded extends PendingTasksState {
  final List<PendingTimeEntry> entries;
  final Set<String> completedEntryIds;
  final int retryCount;

  const PendingTasksLoaded({
    required this.entries,
    this.completedEntryIds = const {},
    this.retryCount = 0,
  });

  /// Check if all entries have been completed (have tasks added)
  bool get allEntriesCompleted =>
      entries.isNotEmpty && completedEntryIds.length >= entries.length;

  /// Get count of remaining entries that need tasks
  int get remainingCount => entries.length - completedEntryIds.length;

  /// Get total count of entries
  int get totalCount => entries.length;

  PendingTasksLoaded copyWith({
    List<PendingTimeEntry>? entries,
    Set<String>? completedEntryIds,
    int? retryCount,
  }) {
    return PendingTasksLoaded(
      entries: entries ?? this.entries,
      completedEntryIds: completedEntryIds ?? this.completedEntryIds,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

/// Error state when fetching pending entries fails
class PendingTasksError extends PendingTasksState {
  final String message;
  final int retryCount;

  const PendingTasksError({
    required this.message,
    this.retryCount = 0,
  });
}

/// All pending tasks have been completed
class PendingTasksCompleted extends PendingTasksState {
  const PendingTasksCompleted();
}

/// User skipped pending tasks (after 3 retry failures)
class PendingTasksSkipped extends PendingTasksState {
  const PendingTasksSkipped();
}

// ============================================================================
// PENDING TASKS NOTIFIER
// ============================================================================

class PendingTasksNotifier extends StateNotifier<PendingTasksState> {
  final Ref _ref;
  final _api = GraphqlApiService();
  late final LoggerService _logger;
  int _retryCount = 0;

  PendingTasksNotifier(this._ref) : super(const PendingTasksInitial()) {
    _logger = _ref.read(loggerServiceProvider);
    _logger.info('PendingTasksNotifier initialized');
  }

  /// Load pending time entries from API
  Future<void> loadPendingEntries() async {
    _logger.info('Loading pending time entries...');
    state = const PendingTasksLoading();

    try {
      final rawEntries = await _api.getPendingTimeEntries();
      // Backend filters: ENDED entries with no tasks, excluding current session.
      // Client filters: exclude today's entries (backend only excludes current session,
      // not all of today's — e.g. a closed session from earlier today still comes through).
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final allEntries = rawEntries
          .map((e) => PendingTimeEntry.fromJson(e))
          .where((entry) => entry.date.isBefore(todayStart))
          .toList();

      // Merge entries by project+date (same as mobile app)
      final entries = _mergeByProjectAndDate(allEntries);

      _logger.info('Loaded ${rawEntries.length} raw entries, ${allEntries.length} before today, merged into ${entries.length}');

      if (entries.isEmpty) {
        state = const PendingTasksCompleted();
      } else {
        state = PendingTasksLoaded(
          entries: entries,
          completedEntryIds: const {},
          retryCount: _retryCount,
        );
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to load pending entries', e, stackTrace);
      _retryCount++;
      state = PendingTasksError(
        message: e.toString(),
        retryCount: _retryCount,
      );
    }
  }

  /// Mark an entry as completed (has tasks added)
  void markEntryCompleted(String entryId) {
    final currentState = state;
    if (currentState is PendingTasksLoaded) {
      final newCompletedIds = {...currentState.completedEntryIds, entryId};

      _logger.info(
          'Marked entry $entryId as completed. ${newCompletedIds.length}/${currentState.entries.length} complete');

      // Check if all entries are now completed
      if (newCompletedIds.length >= currentState.entries.length) {
        _logger.info('All pending entries completed!');
        state = const PendingTasksCompleted();
      } else {
        state = currentState.copyWith(completedEntryIds: newCompletedIds);
      }
    }
  }

  /// Remove entry from completed list (if task was deleted)
  void unmarkEntryCompleted(String entryId) {
    final currentState = state;
    if (currentState is PendingTasksLoaded) {
      final newCompletedIds = {...currentState.completedEntryIds}
        ..remove(entryId);
      state = currentState.copyWith(completedEntryIds: newCompletedIds);
    }
  }

  /// Retry loading after an error
  Future<void> retry() async {
    await loadPendingEntries();
  }

  /// Skip pending tasks (only allowed after 3 retry failures)
  void skip() {
    _logger.info('User skipped pending tasks');
    state = const PendingTasksSkipped();
  }

  /// Reset state to initial
  void reset() {
    _retryCount = 0;
    state = const PendingTasksInitial();
  }

  /// Mark all pending entries as completed and close dialog
  void markAllCompleted() {
    _logger.info('All pending tasks marked as completed');
    state = const PendingTasksCompleted();
  }

  /// Merge entries by project+date (same grouping as mobile app)
  List<PendingTimeEntry> _mergeByProjectAndDate(List<PendingTimeEntry> entries) {
    final Map<String, List<PendingTimeEntry>> grouped = {};

    for (final entry in entries) {
      final d = entry.date;
      final key = '${entry.projectId}_${d.year}-${d.month}-${d.day}';
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    return grouped.values.map((group) {
      if (group.length == 1) return group.first;

      final first = group.first;
      final totalDuration = group.fold<int>(0, (sum, e) => sum + e.duration);
      final allIds = group.map((e) => e.id).toList();

      return first.copyWith(
        entryIds: allIds,
        duration: totalDuration,
      );
    }).toList();
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Main pending tasks state provider
final pendingTasksProvider =
    StateNotifierProvider<PendingTasksNotifier, PendingTasksState>((ref) {
  return PendingTasksNotifier(ref);
});

/// Derived provider to check if there are pending tasks
final hasPendingTasksProvider = Provider<bool>((ref) {
  final state = ref.watch(pendingTasksProvider);
  return state is PendingTasksLoaded && state.entries.isNotEmpty;
});

/// Derived provider to check if skip is allowed (retryCount >= 3)
final canSkipPendingTasksProvider = Provider<bool>((ref) {
  final state = ref.watch(pendingTasksProvider);
  if (state is PendingTasksError) {
    return state.retryCount >= 3;
  }
  if (state is PendingTasksLoaded) {
    return state.retryCount >= 3;
  }
  return false;
});

/// Derived provider to check if pending tasks dialog should be shown
/// Shows when: there are pending entries (from previous days, regardless of check-in status)
final showPendingTasksDialogProvider = Provider<bool>((ref) {
  final pendingState = ref.watch(pendingTasksProvider);

  if (pendingState is PendingTasksLoaded) {
    return pendingState.entries.isNotEmpty;
  }

  return false;
});

/// Derived provider for loading state
final isPendingTasksLoadingProvider = Provider<bool>((ref) {
  final state = ref.watch(pendingTasksProvider);
  return state is PendingTasksLoading;
});

/// Derived provider for pending entries list
final pendingEntriesProvider = Provider<List<PendingTimeEntry>>((ref) {
  final state = ref.watch(pendingTasksProvider);
  if (state is PendingTasksLoaded) {
    return state.entries;
  }
  return [];
});

/// Derived provider to check if all entries are completed
final allEntriesCompletedProvider = Provider<bool>((ref) {
  final state = ref.watch(pendingTasksProvider);
  if (state is PendingTasksLoaded) {
    return state.allEntriesCompleted;
  }
  if (state is PendingTasksCompleted) {
    return true;
  }
  return false;
});
