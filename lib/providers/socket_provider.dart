import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/time_entry_event.dart';
import '../services/socket_service.dart';
import '../services/logger_service.dart';

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

// Provider to initialize and manage socket connection
final socketInitializerProvider = Provider<SocketInitializer>((ref) {
  return SocketInitializer(ref);
});

class SocketInitializer {
  final Ref _ref;
  final _logger = LoggerService();
  StreamSubscription<TimeEntryEvent>? _eventSubscription;

  SocketInitializer(this._ref);

  /// Initialize socket connection and start listening for events
  Future<void> initialize() async {
    final socketService = _ref.read(socketServiceProvider);

    try {
      await socketService.connect();
      _ref.read(socketConnectedProvider.notifier).state = true;

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
    _ref.read(socketServiceProvider).disconnect();
    _ref.read(socketConnectedProvider.notifier).state = false;
    _logger.info('Socket initializer disposed');
  }
}
