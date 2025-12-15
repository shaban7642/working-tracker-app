import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attendance_day.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import 'auth_provider.dart'; // for loggerServiceProvider

// ============================================================================
// ATTENDANCE STATE
// ============================================================================

/// Base class for attendance states
sealed class AttendanceState {
  const AttendanceState();
}

/// Initial state before any data is loaded
class AttendanceInitial extends AttendanceState {
  const AttendanceInitial();
}

/// Loading state while fetching attendance data
class AttendanceLoading extends AttendanceState {
  const AttendanceLoading();
}

/// Successfully loaded attendance data
class AttendanceLoaded extends AttendanceState {
  final AttendanceDay? attendanceDay;

  const AttendanceLoaded(this.attendanceDay);
}

/// Error state when fetching attendance data fails
class AttendanceError extends AttendanceState {
  final String message;

  const AttendanceError(this.message);
}

/// Recording biometric (check-in or check-out) in progress
class AttendanceRecording extends AttendanceState {
  const AttendanceRecording();
}

/// Successfully recorded biometric
class AttendanceRecorded extends AttendanceState {
  final AttendanceDay attendanceDay;

  const AttendanceRecorded(this.attendanceDay);
}

/// Error when recording biometric fails
class AttendanceRecordError extends AttendanceState {
  final String message;

  const AttendanceRecordError(this.message);
}

// ============================================================================
// ATTENDANCE NOTIFIER
// ============================================================================

class AttendanceNotifier extends StateNotifier<AttendanceState> {
  final Ref _ref;
  final _api = ApiService();
  late final LoggerService _logger;

  AttendanceNotifier(this._ref) : super(const AttendanceInitial()) {
    _logger = _ref.read(loggerServiceProvider);
    _logger.info('AttendanceNotifier initialized');
  }

  /// Load today's attendance record
  Future<void> loadTodayAttendance() async {
    try {
      state = const AttendanceLoading();
      _logger.info('Loading today\'s attendance...');

      final attendanceJson = await _api.getMyAttendance();

      if (attendanceJson != null) {
        final attendanceDay = AttendanceDay.fromJson(attendanceJson);
        state = AttendanceLoaded(attendanceDay);
        _logger.info('Attendance loaded: ${attendanceDay.intervals.length} intervals');
      } else {
        state = const AttendanceLoaded(null);
        _logger.info('No attendance record for today');
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to load attendance', e, stackTrace);
      state = AttendanceError(e.toString());
    }
  }

  /// Record biometric (check-in or check-out)
  /// - First call of the day creates a new record (check-in)
  /// - Subsequent calls add intervals (check-out)
  Future<bool> recordBiometric() async {
    try {
      state = const AttendanceRecording();
      _logger.info('Recording biometric...');

      final attendanceJson = await _api.recordBiometric();

      if (attendanceJson != null) {
        final attendanceDay = AttendanceDay.fromJson(attendanceJson);
        state = AttendanceRecorded(attendanceDay);
        _logger.info('Biometric recorded: ${attendanceDay.intervals.length} intervals');

        // Reload to update the main state
        await loadTodayAttendance();
        return true;
      } else {
        state = const AttendanceRecordError('Failed to record attendance');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to record biometric', e, stackTrace);
      state = AttendanceRecordError(e.toString());
      return false;
    }
  }

  /// Get current attendance day if loaded
  AttendanceDay? get currentAttendance {
    final currentState = state;
    if (currentState is AttendanceLoaded) {
      return currentState.attendanceDay;
    }
    if (currentState is AttendanceRecorded) {
      return currentState.attendanceDay;
    }
    return null;
  }

  /// Check if user has checked in today
  bool get hasCheckedIn {
    final attendance = currentAttendance;
    return attendance?.hasCheckedIn ?? false;
  }

  /// Check if user has checked out today
  bool get hasCheckedOut {
    final attendance = currentAttendance;
    return attendance?.hasCheckedOut ?? false;
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Main attendance state provider
final attendanceProvider = StateNotifierProvider<AttendanceNotifier, AttendanceState>((ref) {
  return AttendanceNotifier(ref);
});

/// Derived provider for quick access to current attendance day
final currentAttendanceProvider = Provider<AttendanceDay?>((ref) {
  final state = ref.watch(attendanceProvider);
  if (state is AttendanceLoaded) {
    return state.attendanceDay;
  }
  if (state is AttendanceRecorded) {
    return state.attendanceDay;
  }
  return null;
});

/// Derived provider to check if user has checked in today
final hasCheckedInProvider = Provider<bool>((ref) {
  final attendance = ref.watch(currentAttendanceProvider);
  return attendance?.hasCheckedIn ?? false;
});

/// Derived provider to check if user can check out (must have checked in first)
final canCheckOutProvider = Provider<bool>((ref) {
  final attendance = ref.watch(currentAttendanceProvider);
  return attendance?.hasCheckedIn ?? false;
});

/// Derived provider for loading state
final isAttendanceLoadingProvider = Provider<bool>((ref) {
  final state = ref.watch(attendanceProvider);
  return state is AttendanceLoading || state is AttendanceRecording;
});
