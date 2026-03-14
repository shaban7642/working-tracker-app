class SubscriptionQueries {
  static const String timeEntryChanged = r'''
    subscription Attendance_TimeEntry_Changed {
      Attendance_TimeEntry_Changed {
        employeeId
        timeEntryId
        sessionId
        projectId
        status
        startTime
        endTime
        action
      }
    }
  ''';

  static const String sessionCheckedIn = r'''
    subscription Attendance_Session_CheckedIn {
      Attendance_Session_CheckedIn {
        employeeId
        sessionId
        attendanceId
        checkInAt
      }
    }
  ''';

  static const String sessionCheckedOut = r'''
    subscription Attendance_Session_CheckedOut {
      Attendance_Session_CheckedOut {
        employeeId
        sessionId
        attendanceId
        checkInAt
        checkOutAt
        isAutoCheckout
        durationHours
        durationMinutes
      }
    }
  ''';

  static const String taskChanged = r'''
    subscription Attendance_Task_Changed {
      Attendance_Task_Changed {
        employeeId
        taskId
        timeEntryId
        title
        action
        projectId
      }
    }
  ''';

  static const String notificationReceived = r'''
    subscription Notification_Received {
      Notification_Received {
        employeeId
        notificationId
        title
        body
        type
        data
        createdAt
      }
    }
  ''';
}
