class NotificationQueries {
  static const String getNotifications = r'''
    query Notification_GetNotifications(
      $filter: NotificationFilterInput
      $orderBy: NotificationOrderByInput
      $pagination: PaginationInput
    ) {
      Notification_GetNotifications(
        filter: $filter
        orderBy: $orderBy
        pagination: $pagination
      ) {
        items {
          id
          title
          body
          type
          isRead
          readAt
          createdAt
          employeeId
          data
        }
        page
        pageSize
        total
        totalPages
        hasNextPage
        hasPreviousPage
      }
    }
  ''';

  static const String getUnreadCount = r'''
    query Notification_GetUnreadCount {
      Notification_GetUnreadCount {
        count
      }
    }
  ''';

  static const String markAsRead = r'''
    mutation Notification_MarkAsRead($id: String!) {
      Notification_MarkAsRead(id: $id) {
        success
        count
      }
    }
  ''';

  static const String markAllAsRead = r'''
    mutation Notification_MarkAllAsRead {
      Notification_MarkAllAsRead {
        success
        count
      }
    }
  ''';
}
