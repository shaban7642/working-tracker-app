import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../providers/notification_provider.dart';
import '../screens/notifications_screen.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return IconButton(
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        label: Text(
          unreadCount > 9 ? '9+' : '$unreadCount',
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
        child: const Icon(Icons.notifications_outlined),
      ),
      color: AppTheme.textSecondary,
      iconSize: 20,
      tooltip: 'Notifications',
      onPressed: () => _showNotificationPanel(context),
    );
  }

  void _showNotificationPanel(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const NotificationsScreen(),
      ),
    );
  }
}
