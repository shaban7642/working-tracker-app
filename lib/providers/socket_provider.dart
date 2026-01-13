import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attendance_event.dart';
import '../models/time_entry_event.dart';
import '../services/socket_service.dart';
import '../services/logger_service.dart';
import '../services/token_refresh_coordinator.dart';

// Socket service provider (singleton)
final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService();
});

// Socket connection state provider
final socketConnectedProvider = StateProvider<bool>((ref) {
  return SocketService().isConnected;
});

// Stream provider for time entry events
final timeEntryEventStreamProvider = StreamProvider<TimeEntryEvent>((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return socketService.eventStream;
});

// Stream provider for attendance events
final attendanceEventStreamProvider = StreamProvider<AttendanceEvent>((ref) {
  final socketService = ref.watch(socketServiceProvider);
  return socketService.attendanceEventStream;
});

// Provider to initialize and manage socket connection
final socketInitializerProvider = Provider<SocketInitializer>((ref) {
  return SocketInitializer(ref);
});

class SocketInitializer {
  final Ref _ref;
  final _logger = LoggerService();
  StreamSubscription<TimeEntryEvent>? _eventSubscription;
  TokenRefreshHandler? _tokenRefreshHandler;

  SocketInitializer(this._ref);

  /// Initialize socket connection and start listening for events
  Future<void> initialize() async {
    final socketService = _ref.read(socketServiceProvider);

    try {
      await socketService.connect();
      _ref.read(socketConnectedProvider.notifier).state = true;

      // Initialize token refresh handler to handle token expiration
      _tokenRefreshHandler = _ref.read(tokenRefreshHandlerProvider);
      _tokenRefreshHandler?.initialize();

      // Subscribe to events and update connection state
      _eventSubscription = socketService.eventStream.listen(
        (event) {
          _logger.info('Socket event received: $event');
        },
        onError: (error) {
          _logger.error('Socket event stream error', error, null);
        },
      );

      _logger.info('Socket initializer ready');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize socket', e, stackTrace);
      _ref.read(socketConnectedProvider.notifier).state = false;
    }
  }

  /// Disconnect socket and cleanup
  void dispose() {
    _eventSubscription?.cancel();
    _tokenRefreshHandler?.dispose();
    _ref.read(socketServiceProvider).disconnect();
    _ref.read(socketConnectedProvider.notifier).state = false;
    _logger.info('Socket initializer disposed');
  }
}

// Token refresh handler provider
final tokenRefreshHandlerProvider = Provider<TokenRefreshHandler>((ref) {
  return TokenRefreshHandler(ref);
});

/// Handles token refresh when socket receives token errors
/// and proactively reconnects socket when token is refreshed elsewhere (e.g., API 401)
class TokenRefreshHandler {
  final Ref _ref;
  final _logger = LoggerService();
  final _tokenCoordinator = TokenRefreshCoordinator();

  StreamSubscription<String>? _tokenErrorSubscription;
  StreamSubscription<void>? _tokenRefreshedSubscription;

  TokenRefreshHandler(this._ref);

  /// Start listening for token errors and token refresh events
  void initialize() {
    final socketService = _ref.read(socketServiceProvider);

    // Listen for socket token errors - trigger refresh
    _tokenErrorSubscription = socketService.tokenErrorStream.listen(
      (error) async {
        _logger.warning('Token error received from socket: $error');
        await _handleTokenError();
      },
    );

    // Listen for external token refreshes (e.g., from API 401 handling)
    // Proactively reconnect socket with new token
    _tokenRefreshedSubscription = _tokenCoordinator.tokenRefreshedStream.listen(
      (_) async {
        _logger.info('Token refreshed externally, reconnecting socket...');
        await _reconnectSocket();
      },
    );

    _logger.info('Token refresh handler initialized');
  }

  /// Handle token error by attempting coordinated refresh
  Future<void> _handleTokenError() async {
    _logger.info('Attempting coordinated token refresh due to socket error...');

    final success = await _tokenCoordinator.refreshToken();

    if (success) {
      await _reconnectSocket();
    } else {
      _logger.warning('Token refresh failed, forcing logout');
      await _tokenCoordinator.forceLogout();
    }
  }

  /// Reconnect socket with new token
  Future<void> _reconnectSocket() async {
    try {
      final socketService = _ref.read(socketServiceProvider);
      await socketService.reconnect();
      _ref.read(socketConnectedProvider.notifier).state = true;
      _logger.info('Socket reconnected with new token');
    } catch (e, stackTrace) {
      _logger.error('Failed to reconnect socket', e, stackTrace);
    }
  }

  /// Dispose resources
  void dispose() {
    _tokenErrorSubscription?.cancel();
    _tokenRefreshedSubscription?.cancel();
    _logger.info('Token refresh handler disposed');
  }
}
