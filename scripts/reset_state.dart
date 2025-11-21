/// Script to reset all local state/storage
///
/// Run with: flutter run scripts/reset_state.dart
/// Or: dart run scripts/reset_state.dart (requires proper setup)
///
/// For easier usage, use the shell script: ./scripts/reset_state.sh

import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  print('🔄 Resetting all local state...\n');

  try {
    // Initialize Hive
    await Hive.initFlutter();

    // Box names (from AppConstants)
    const boxNames = [
      'user_box',
      'projects_box',
      'time_entries_box',
      'reports_box',
    ];

    // Clear each box
    for (final boxName in boxNames) {
      try {
        final box = await Hive.openBox(boxName);
        final count = box.length;
        await box.clear();
        print('✅ Cleared $boxName ($count entries)');
      } catch (e) {
        print('⚠️  Could not clear $boxName: $e');
      }
    }

    // Close Hive
    await Hive.close();

    print('\n✅ All state reset successfully!');
  } catch (e) {
    print('❌ Error resetting state: $e');
    exit(1);
  }
}
