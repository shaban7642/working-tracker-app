import 'dart:async';
import 'package:graphql/client.dart';
import '../core/utils/date_parsing.dart';
import '../graphql/graphql_client.dart';
import '../graphql/queries/subscription_queries.dart';
import '../models/attendance_event.dart';
import '../models/task_event.dart';
import '../models/time_entry_event.dart';
import '../models/notification_event.dart';
import '../models/notification.dart';
import 'logger_service.dart';
import 'storage_service.dart';

/// Service for managing GraphQL subscriptions for real-time updates.
/// Replaces SocketService (Socket.IO) with GraphQL WebSocket subscriptions.
class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;

  final _logger = LoggerService();
  final _graphql = GraphQLClientService();
  final _storage = StorageService();

  // Stream controllers matching SocketService's interface
  final _eventController = StreamController<TimeEntryEvent>.broadcast();
  final _attendanceEventController = StreamController<AttendanceEvent>.broadcast();
  final _taskEventController = StreamController<TaskEvent>.broadcast();
  final _notificationEventController = StreamController<NotificationEvent>.broadcast();
  final _tokenErrorController = StreamController<String>.broadcast();

  // Subscription streams from GraphQL
  StreamSubscription<QueryResult>? _timeEntrySubscription;
  StreamSubscription<QueryResult>? _checkInSubscription;
  StreamSubscription<QueryResult>? _checkOutSubscription;
  StreamSubscription<QueryResult>? _taskSubscription;
  StreamSubscription<QueryResult>? _notificationSubscription;

  bool _isConnected = false;

  SubscriptionService._internal();

  /// Stream of time entry events
  Stream<TimeEntryEvent> get eventStream => _eventController.stream;

  /// Stream of attendance events
  Stream<AttendanceEvent> get attendanceEventStream => _attendanceEventController.stream;

  /// Stream of task events
  Stream<TaskEvent> get taskEventStream => _taskEventController.stream;

  /// Stream of notification events
  Stream<NotificationEvent> get notificationEventStream => _notificationEventController.stream;

  /// Stream of token error events
  Stream<String> get tokenErrorStream => _tokenErrorController.stream;

  /// Whether subscriptions are active
  bool get isConnected => _isConnected;

  /// Start all subscriptions
  Future<void> connect() async {
    if (_isConnected) {
      _logger.info('Subscriptions already active');
      return;
    }

    final user = _storage.getCurrentUser();
    if (user == null || user.token == null) {
      _logger.warning('Cannot start subscriptions: no authenticated user');
      return;
    }

    try {
      _logger.info('Starting GraphQL subscriptions...');

      _subscribeToTimeEntryChanges();
      _subscribeToCheckIn();
      _subscribeToCheckOut();
      _subscribeToTaskChanges();
      _subscribeToNotifications();

      _isConnected = true;
      _logger.info('All GraphQL subscriptions started');
    } catch (e, stackTrace) {
      _logger.error('Failed to start subscriptions', e, stackTrace);
    }
  }

  /// Subscribe to time entry changes
  void _subscribeToTimeEntryChanges() {
    _timeEntrySubscription?.cancel();

    final stream = _graphql.subscribe(SubscriptionQueries.timeEntryChanged);
    _timeEntrySubscription = stream.listen(
      (result) {
        if (result.hasException) {
          _handleSubscriptionError('timeEntry', result.exception);
          return;
        }

        final data = result.data?['Attendance_TimeEntry_Changed'];
        if (data == null) return;

        try {
          final action = data['action'] as String? ?? 'started';
          TimeEntryEventType eventType;
          switch (action.toLowerCase()) {
            case 'started':
            case 'created':
            case 'resumed':
              eventType = TimeEntryEventType.started;
              break;
            case 'paused':
              eventType = TimeEntryEventType.paused;
              break;
            default:
              eventType = TimeEntryEventType.ended;
          }

          final event = TimeEntryEvent(
            type: eventType,
            id: data['timeEntryId'] as String? ?? '',
            userId: data['employeeId'] as String? ?? '',
            projectId: data['projectId'] as String? ?? '',
            projectName: '',
            startedAt: data['startTime'] != null
                ? parseUtcDateTime(data['startTime'] as String)
                : DateTime.now(),
            endedAt: data['endTime'] != null
                ? tryParseUtcDateTime(data['endTime'] as String)
                : null,
            source: 'graphql',
            openStatus: eventType != TimeEntryEventType.ended,
          );

          _eventController.add(event);
          _logger.info('Time entry subscription event: $action');
        } catch (e) {
          _logger.warning('Failed to parse time entry event: $e');
        }
      },
      onError: (error) {
        _logger.error('Time entry subscription error', error, null);
        _handleSubscriptionError('timeEntry', null);
      },
    );
  }

  /// Subscribe to check-in events
  void _subscribeToCheckIn() {
    _checkInSubscription?.cancel();

    final stream = _graphql.subscribe(SubscriptionQueries.sessionCheckedIn);
    _checkInSubscription = stream.listen(
      (result) {
        if (result.hasException) {
          _handleSubscriptionError('checkIn', result.exception);
          return;
        }

        final data = result.data?['Attendance_Session_CheckedIn'];
        if (data == null) return;

        try {
          final event = AttendanceEvent(
            type: AttendanceEventType.checkedIn,
            id: data['attendanceId'] as String? ?? '',
            userId: data['employeeId'] as String? ?? '',
            day: DateTime.now(),
            isActive: true,
          );

          _attendanceEventController.add(event);
          _logger.info('Check-in subscription event received');
        } catch (e) {
          _logger.warning('Failed to parse check-in event: $e');
        }
      },
      onError: (error) {
        _logger.error('Check-in subscription error', error, null);
      },
    );
  }

  /// Subscribe to check-out events
  void _subscribeToCheckOut() {
    _checkOutSubscription?.cancel();

    final stream = _graphql.subscribe(SubscriptionQueries.sessionCheckedOut);
    _checkOutSubscription = stream.listen(
      (result) {
        if (result.hasException) {
          _handleSubscriptionError('checkOut', result.exception);
          return;
        }

        final data = result.data?['Attendance_Session_CheckedOut'];
        if (data == null) return;

        try {
          final event = AttendanceEvent(
            type: AttendanceEventType.checkedOut,
            id: data['attendanceId'] as String? ?? '',
            userId: data['employeeId'] as String? ?? '',
            day: DateTime.now(),
            isActive: false,
          );

          _attendanceEventController.add(event);
          _logger.info('Check-out subscription event received');
        } catch (e) {
          _logger.warning('Failed to parse check-out event: $e');
        }
      },
      onError: (error) {
        _logger.error('Check-out subscription error', error, null);
      },
    );
  }

  /// Subscribe to task changes
  void _subscribeToTaskChanges() {
    _taskSubscription?.cancel();

    final stream = _graphql.subscribe(SubscriptionQueries.taskChanged);
    _taskSubscription = stream.listen(
      (result) {
        if (result.hasException) {
          _handleSubscriptionError('task', result.exception);
          return;
        }

        final data = result.data?['Attendance_Task_Changed'];
        if (data == null) return;

        try {
          final action = data['action'] as String? ?? 'updated';
          TaskEventType eventType;
          switch (action.toLowerCase()) {
            case 'created':
              eventType = TaskEventType.created;
              break;
            case 'deleted':
              eventType = TaskEventType.deleted;
              break;
            default:
              eventType = TaskEventType.updated;
          }

          final event = TaskEvent(
            type: eventType,
            id: data['taskId'] as String? ?? '',
            projectId: data['projectId'] as String? ?? '',
            reportId: data['dailyProjectWorkId'] as String? ?? '',
            title: data['title'] as String? ?? '',
            description: '',
            imageCount: 0,
            images: [],
            createdAt: DateTime.now(),
          );

          _taskEventController.add(event);
          _logger.info('Task subscription event: $action');
        } catch (e) {
          _logger.warning('Failed to parse task event: $e');
        }
      },
      onError: (error) {
        _logger.error('Task subscription error', error, null);
      },
    );
  }

  /// Subscribe to notification events
  void _subscribeToNotifications() {
    _notificationSubscription?.cancel();

    final stream = _graphql.subscribe(SubscriptionQueries.notificationReceived);
    _notificationSubscription = stream.listen(
      (result) {
        if (result.hasException) {
          _handleSubscriptionError('notification', result.exception);
          return;
        }

        final data = result.data?['Notification_Received'];
        if (data == null) return;

        try {
          final notification = AppNotification(
            id: data['notificationId'] as String? ?? '',
            type: data['type'] as String? ?? 'GENERAL',
            title: data['title'] as String?,
            body: data['body'] as String?,
            payloadJson: data['data']?.toString() ?? '{}',
            createdAt: data['createdAt'] != null
                ? parseUtcDateTime(data['createdAt'] as String)
                : DateTime.now(),
          );

          final event = NotificationEvent(notification: notification);
          _notificationEventController.add(event);
          _logger.info('Notification subscription event: ${notification.type}');
        } catch (e) {
          _logger.warning('Failed to parse notification event: $e');
        }
      },
      onError: (error) {
        _logger.error('Notification subscription error', error, null);
      },
    );
  }

  /// Handle subscription errors
  void _handleSubscriptionError(String subscriptionName, OperationException? exception) {
    if (exception != null && _graphql.isAuthError(exception)) {
      _logger.warning('Auth error in $subscriptionName subscription');
      _tokenErrorController.add('Auth error in $subscriptionName subscription');
    } else {
      _logger.warning('Error in $subscriptionName subscription: $exception');
    }
  }

  /// Disconnect all subscriptions
  void disconnect() {
    _timeEntrySubscription?.cancel();
    _checkInSubscription?.cancel();
    _checkOutSubscription?.cancel();
    _taskSubscription?.cancel();
    _notificationSubscription?.cancel();
    _timeEntrySubscription = null;
    _checkInSubscription = null;
    _checkOutSubscription = null;
    _taskSubscription = null;
    _notificationSubscription = null;
    _isConnected = false;
    _logger.info('All GraphQL subscriptions stopped');
  }

  /// Reconnect subscriptions (after token refresh)
  Future<void> reconnect() async {
    _logger.info('Reconnecting GraphQL subscriptions...');
    disconnect();
    await connect();
  }

  /// Dispose all resources
  void dispose() {
    disconnect();
    _eventController.close();
    _attendanceEventController.close();
    _taskEventController.close();
    _notificationEventController.close();
    _tokenErrorController.close();
  }
}
