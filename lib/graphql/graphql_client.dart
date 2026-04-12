import 'dart:io';
import 'package:graphql/client.dart';
import 'package:http/io_client.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/storage_service.dart';
import '../services/logger_service.dart';

class GraphQLClientService {
  static final GraphQLClientService _instance = GraphQLClientService._internal();
  factory GraphQLClientService() => _instance;
  GraphQLClientService._internal();

  final _logger = LoggerService();
  final _storage = StorageService();

  GraphQLClient? _client;
  WebSocketLink? _wsLink;
  String? _currentToken;

  static String get _graphqlUrl =>
      dotenv.env['GRAPHQL_URL'] ?? 'https://community-app-backend.silverstonearchitects.com/graphql';

  static String get _graphqlWsUrl =>
      dotenv.env['GRAPHQL_WS_URL'] ?? 'wss://community-app-backend.silverstonearchitects.com/graphql';

  /// Get or create the GraphQL client
  GraphQLClient get client {
    _client ??= _createClient();
    return _client!;
  }

  /// Create a new GraphQL client with auth and error handling
  GraphQLClient _createClient() {
    final httpLink = HttpLink(
      _graphqlUrl,
      httpClient: _createHttpClient(),
    );

    final authLink = AuthLink(
      getToken: () {
        // First try storage, then fall back to in-memory token
        // (needed during login flow before user is saved to storage)
        final user = _storage.getCurrentUser();
        final token = user?.token ?? _currentToken;
        if (token != null) {
          return 'Bearer $token';
        }
        return null;
      },
    );

    final link = authLink.concat(httpLink);

    return GraphQLClient(
      link: link,
      cache: GraphQLCache(store: InMemoryStore()),
      defaultPolicies: DefaultPolicies(
        query: Policies(
          fetch: FetchPolicy.networkOnly,
        ),
        mutate: Policies(
          fetch: FetchPolicy.networkOnly,
        ),
      ),
    );
  }

  /// Create HTTP client that bypasses SSL certificate verification
  IOClient _createHttpClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    return IOClient(httpClient);
  }

  GraphQLClient? _wsClient;

  /// Get or create the shared WebSocket client for subscriptions.
  /// All subscriptions share a single WebSocket connection.
  GraphQLClient get _subscriptionClient {
    if (_wsClient != null) return _wsClient!;

    _logger.info('Creating WebSocket link to $_graphqlWsUrl');

    _wsLink = WebSocketLink(
      _graphqlWsUrl,
      config: SocketClientConfig(
        autoReconnect: true,
        inactivityTimeout: const Duration(seconds: 30),
        initialPayload: () {
          // Read token dynamically so reconnections use the latest token
          final user = _storage.getCurrentUser();
          final token = user?.token ?? _currentToken;
          _logger.info('WS initialPayload: token ${token != null ? "present (${token.length} chars)" : "missing"}');
          if (token != null) {
            return {'authToken': 'Bearer $token'};
          }
          return {};
        },
      ),
      subProtocol: GraphQLProtocol.graphqlTransportWs,
    );

    _wsClient = GraphQLClient(
      link: _wsLink!,
      cache: GraphQLCache(store: InMemoryStore()),
    );

    return _wsClient!;
  }

  /// Update the auth token (after login or token refresh)
  void updateToken(String? token) {
    _currentToken = token;
    // Recreate HTTP client to pick up new token
    _client = _createClient();
    // Reset WS client so subscriptions reconnect with new token
    _wsLink?.dispose();
    _wsLink = null;
    _wsClient = null;
    _logger.info('GraphQL client token updated');
  }

  /// Reset the client (on logout)
  void reset() {
    _wsLink?.dispose();
    _wsLink = null;
    _wsClient = null;
    _client = null;
    _currentToken = null;
    _logger.info('GraphQL client reset');
  }

  /// Execute a query with error handling
  Future<QueryResult> query(
    String queryString, {
    Map<String, dynamic>? variables,
    FetchPolicy? fetchPolicy,
  }) async {
    final options = QueryOptions(
      document: gql(queryString),
      variables: variables ?? {},
      fetchPolicy: fetchPolicy,
    );

    final result = await client.query(options);

    if (result.hasException) {
      _logger.error(
        'GraphQL query error: ${result.exception}',
        result.exception,
        null,
      );

      // Check for auth errors
      if (isAuthError(result.exception)) {
        throw AuthenticationException('Authentication failed');
      }
    }

    return result;
  }

  /// Execute a mutation with error handling
  Future<QueryResult> mutate(
    String mutationString, {
    Map<String, dynamic>? variables,
  }) async {
    final options = MutationOptions(
      document: gql(mutationString),
      variables: variables ?? {},
    );

    final result = await client.mutate(options);

    if (result.hasException) {
      _logger.error(
        'GraphQL mutation error: ${result.exception}',
        result.exception,
        null,
      );

      // Check for auth errors
      if (isAuthError(result.exception)) {
        throw AuthenticationException('Authentication failed');
      }
    }

    return result;
  }

  /// Create a subscription stream using the shared WebSocket connection
  Stream<QueryResult> subscribe(
    String subscriptionString, {
    Map<String, dynamic>? variables,
  }) {
    final options = SubscriptionOptions(
      document: gql(subscriptionString),
      variables: variables ?? {},
    );

    return _subscriptionClient.subscribe(options);
  }

  /// Check if an exception is an authentication error
  bool isAuthError(OperationException? exception) {
    if (exception == null) return false;

    // Check GraphQL errors
    for (final error in exception.graphqlErrors) {
      final extensions = error.extensions;
      if (extensions != null) {
        final code = extensions['code'];
        if (code == 'UNAUTHENTICATED' || code == 'FORBIDDEN') {
          return true;
        }
      }
      // Also check message
      if (error.message.toLowerCase().contains('unauthorized') ||
          error.message.toLowerCase().contains('unauthenticated')) {
        return true;
      }
    }

    // Check link exception (network-level auth errors)
    if (exception.linkException != null) {
      final linkException = exception.linkException;
      if (linkException is HttpLinkServerException) {
        if (linkException.response.statusCode == 401) {
          return true;
        }
      }
    }

    return false;
  }
}

/// Custom exception for authentication errors
class AuthenticationException implements Exception {
  final String message;
  AuthenticationException(this.message);

  @override
  String toString() => 'AuthenticationException: $message';
}
