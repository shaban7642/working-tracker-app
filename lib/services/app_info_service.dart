import 'package:package_info_plus/package_info_plus.dart';
import 'logger_service.dart';

/// Service for accessing app version info from pubspec.yaml
class AppInfoService {
  static final AppInfoService _instance = AppInfoService._internal();
  factory AppInfoService() => _instance;

  final _logger = LoggerService();

  PackageInfo? _packageInfo;

  AppInfoService._internal();

  /// Initialize the service - must be called before accessing version info
  Future<void> initialize() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
      _logger.info(
        'App info initialized: ${_packageInfo!.appName} v${_packageInfo!.version}+${_packageInfo!.buildNumber}',
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize app info', e, stackTrace);
    }
  }

  /// Get the app version (e.g., "1.0.2")
  String get version => _packageInfo?.version ?? '0.0.0';

  /// Get the build number (e.g., "3")
  String get buildNumber => _packageInfo?.buildNumber ?? '0';

  /// Get the full version string (e.g., "1.0.2+3")
  String get fullVersion => '$version+$buildNumber';

  /// Get the app name
  String get appName => _packageInfo?.appName ?? 'Silver Stone';

  /// Get the package name
  String get packageName => _packageInfo?.packageName ?? '';
}
