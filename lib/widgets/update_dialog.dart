import 'dart:io' show exit;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_theme.dart';
import '../models/app_version_info.dart';
import '../services/app_info_service.dart';
import '../services/logger_service.dart';

/// Mandatory update dialog - users MUST update to continue using the app
/// No "Later" or "Skip" buttons - only "Update Now"
class UpdateDialog extends StatelessWidget {
  final AppVersionInfo versionInfo;

  const UpdateDialog({
    super.key,
    required this.versionInfo,
  });

  /// Show the mandatory update dialog (cannot be dismissed)
  static Future<void> show({
    required BuildContext context,
    required AppVersionInfo versionInfo,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false, // Cannot dismiss by tapping outside
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => UpdateDialog(versionInfo: versionInfo),
    );
  }

  Future<void> _downloadUpdate(BuildContext context) async {
    final logger = LoggerService();
    try {
      final uri = Uri.parse(versionInfo.downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        logger.info('Opened download URL: ${versionInfo.downloadUrl}');

        // Show message that app will close
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Download started. Please install the update and restart the app.'),
              duration: Duration(seconds: 3),
            ),
          );
        }

        // Close the app after a short delay to let user see the message
        await Future.delayed(const Duration(seconds: 2));
        exit(0);
      } else {
        logger.warning('Cannot launch URL: ${versionInfo.downloadUrl}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open download page'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      logger.error('Error opening download URL: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Cannot use back button/escape to close
      child: Dialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Update icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.elevatedSurfaceColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppTheme.secondaryColor,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'Update Required',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Version info
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                    children: [
                      const TextSpan(text: 'Version '),
                      TextSpan(
                        text: versionInfo.latestVersion,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const TextSpan(text: ' is available\n'),
                      TextSpan(
                        text: 'Current: ${AppInfoService().version}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Mandatory update notice
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.secondaryColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Please update to continue using the app',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Update Now button - ONLY button, no "Later" or "Skip"
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => _downloadUpdate(context),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text(
                      'Update Now',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                // No "Later" or "Skip" buttons - update is mandatory
              ],
            ),
          ),
        ),
      ),
    );
  }
}
