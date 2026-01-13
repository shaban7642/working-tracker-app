import 'dart:async';
import 'auth_service.dart';
import 'logger_service.dart';

/// Coordinates token refresh between API and Socket services.
/// Ensures only one refresh attempt happens at a time and notifies
/// all interested parties when tokens are updated.
class TokenRefreshCoordinator {
  static final TokenRefreshCoordinator _instance =
      TokenRefreshCoordinator._internal();
  factory TokenRefreshCoordinator() => _instance;

  final _logger = LoggerService();
  final _authService = AuthService();

  // Single flag to prevent concurrent refresh attempts
  bool _isRefreshing = false;

  // Completer for waiting on current refresh operation
  Completer<bool>? _refreshCompleter;

  // Stream controller for token refresh events
  final _tokenRefreshedController = StreamController<void>.broadcast();

  TokenRefreshCoordinator._internal();

  /// Stream that emits when token has been successfully refreshed.
  /// Socket and other services can listen to this to reconnect with new token.
  Stream<void> get tokenRefreshedStream => _tokenRefreshedController.stream;

  /// Check if a refresh is currently in progress
  bool get isRefreshing => _isRefreshing;

  /// Attempt to refresh the token. Returns true on success.
  /// If a refresh is already in progress, waits for it to complete.
  Future<bool> refreshToken() async {
    // If already refreshing, wait for the current operation
    if (_isRefreshing && _refreshCompleter != null) {
      _logger.info('Token refresh already in progress, waiting...');
      return _refreshCompleter!.future;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<bool>();

    try {
      _logger.info('Starting coordinated token refresh...');

      final success = await _authService.refreshAccessToken();

      if (success) {
        _logger.info('Token refresh successful, notifying listeners...');
        _tokenRefreshedController.add(null);
        _refreshCompleter!.complete(true);
        return true;
      } else {
        _logger.warning('Token refresh returned false');
        _refreshCompleter!.complete(false);
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Token refresh failed with exception', e, stackTrace);
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }

  /// Force logout - delegates to AuthService
  Future<void> forceLogout() async {
    _logger.warning('Force logout triggered via coordinator');
    await _authService.forceLogout();
  }

  /// Dispose resources
  void dispose() {
    _tokenRefreshedController.close();
  }
}
