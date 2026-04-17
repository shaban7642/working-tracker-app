import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:screen_capturer/screen_capturer.dart';
import 'package:window_manager/window_manager.dart';
import 'logger_service.dart';
import 'window_service.dart';

class ScreenshotService {
  static final ScreenshotService _instance = ScreenshotService._internal();
  factory ScreenshotService() => _instance;
  ScreenshotService._internal();

  final _logger = LoggerService();
  final _windowService = WindowService();

  /// Takes a screenshot and returns the path to the saved JPEG file,
  /// or null if the user cancelled.
  Future<String?> takeScreenshot() async {
    final wasFloating = _windowService.isFloatingMode;

    try {
      // Disable always-on-top if in floating mode so the window
      // doesn't interfere with the snipping tool.
      if (wasFloating) {
        await windowManager.setAlwaysOnTop(false);
      }

      // On Windows, use hide() for instant removal (no animation).
      // On macOS/Linux, minimize() is reliable.
      if (Platform.isWindows) {
        await windowManager.hide();
        await Future.delayed(const Duration(milliseconds: 200));
      } else {
        await windowManager.minimize();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Launch interactive region capture.
      CapturedData? capturedData = await screenCapturer.capture(
        mode: CaptureMode.region,
      );

      // Restore window.
      await _restoreWindow(wasFloating);

      if (capturedData != null && capturedData.imageBytes != null) {
        return await _processAndSaveImage(capturedData.imageBytes!);
      }

      return null; // User cancelled
    } catch (e) {
      // Guarantee window is restored even on error.
      try {
        await _restoreWindow(wasFloating);
      } catch (_) {}

      _logger.error('Screenshot failed', e, null);
      rethrow;
    }
  }

  Future<void> _restoreWindow(bool wasFloating) async {
    if (Platform.isWindows) {
      await windowManager.show();
    } else {
      await windowManager.restore();
    }
    await windowManager.focus();

    if (wasFloating) {
      await windowManager.setAlwaysOnTop(true);
    }
  }

  Future<String> _processAndSaveImage(Uint8List imageBytes) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw Exception('Failed to decode screenshot image');
    }
    final jpegBytes = img.encodeJpg(image, quality: 85);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempDir = Directory.systemTemp;
    final path = '${tempDir.path}/screenshot_$timestamp.jpg';
    await File(path).writeAsBytes(jpegBytes);
    return path;
  }
}
