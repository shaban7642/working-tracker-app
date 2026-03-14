class AttendanceQueries {
  static const String getMyCurrentStatus = r'''
    query Attendance_Attendance_GetMyCurrentStatus {
      Attendance_Attendance_GetMyCurrentStatus {
        hasCheckedInToday
        totalWorkedMinutesToday
        currentSession {
          id
          checkInAt
          checkOutAt
          checkInLatitude
          checkInLongitude
          checkOutLatitude
          checkOutLongitude
          checkInNotes
          checkOutNotes
          geolocationValidated
          isAutoCheckout
        }
        todayAttendance {
          id
          date
          totalWorkedMinutes
        }
        todaySessions {
          id
          checkInAt
          checkOutAt
          duration
          checkInLatitude
          checkInLongitude
          checkOutLatitude
          checkOutLongitude
          checkInNotes
          checkOutNotes
          geolocationValidated
          isAutoCheckout
          timeEntries {
            id
            startTime
            endTime
            duration
            status
            taskSubmissionStatus
            projectId
            project {
              id
              name
              description
            }
            description
          }
        }
        activeTimeEntry {
          id
          startTime
          endTime
          duration
          status
          taskSubmissionStatus
          projectId
          project {
            id
            name
            description
          }
          employeeId
          sessionId
          description
          createdAt
          updatedAt
        }
      }
    }
  ''';

  static const String checkIn = r'''
    mutation Attendance_Session_CheckIn($input: CheckInInput!) {
      Attendance_Session_CheckIn(input: $input) {
        success
        message
        attendance {
          id
          date
          totalWorkedMinutes
          sessions {
            id
            checkInAt
            checkOutAt
            duration
            checkInLatitude
            checkInLongitude
            checkOutLatitude
            checkOutLongitude
            geolocationValidated
            isAutoCheckout
            timeEntries {
              id
              startTime
              endTime
              duration
              status
              taskSubmissionStatus
              projectId
              project {
                id
                name
              }
            }
          }
        }
        session {
          id
          checkInAt
          checkOutAt
          checkInLatitude
          checkInLongitude
          geolocationValidated
          isAutoCheckout
        }
        geolocationResult {
          distanceMeters
          isValid
          locationName
          message
        }
      }
    }
  ''';

  static const String checkOut = r'''
    mutation Attendance_Session_CheckOut($input: CheckOutInput!) {
      Attendance_Session_CheckOut(input: $input) {
        success
        message
        session {
          id
          checkInAt
          checkOutAt
          duration
          checkInLatitude
          checkInLongitude
          checkOutLatitude
          checkOutLongitude
          geolocationValidated
          isAutoCheckout
        }
        duration {
          hours
          minutes
          totalMinutes
        }
      }
    }
  ''';

  static const String getMyDailyReport = r'''
    query Attendance_Report_GetMyDailyReport($date: Date!) {
      Attendance_Report_GetMyDailyReport(date: $date) {
        date
        employeeId
        items {
          description
          endTime
          hoursWorked
          projectId
          projectName
          startTime
          timeEntryId
          tasks {
            id
            title
            description
          }
        }
        totalHours
      }
    }
  ''';

  static const String getDailyReport = r'''
    query Attendance_Report_GetDailyReport($date: Date!, $employeeId: String!) {
      Attendance_Report_GetDailyReport(date: $date, employeeId: $employeeId) {
        date
        employeeId
        totalHours
        items {
          timeEntryId
          projectId
          projectName
          startTime
          endTime
          hoursWorked
          description
          tasks {
            id
            title
            description
          }
        }
      }
    }
  ''';

  /// Get my time report for a month - returns all days in ONE query
  static const String getMyTimeReport = r'''
    query Attendance_Report_GetMyTimeReport($month: String) {
      Attendance_Report_GetMyTimeReport(month: $month) {
        report {
          days {
            date
            dayName
            checkIn
            checkOut
            totalTime
            expectedHours
            lessWorkingTime
            overtime
            isWeekend
            isHoliday
            isLeave
            leaveType
            notes
          }
          summary {
            totalWorkingDays
            daysAttended
            totalTime
            totalExpectedHours
            totalLessWorkingTime
            totalOvertime
            totalAbsentDays
            totalWeekendDays
            totalHolidays
            totalLeaveDays
          }
          projectHours {
            projectId
            projectName
            hoursWorked
          }
        }
        meta {
          month
          totalUsers
          reportPeriod
        }
      }
    }
  ''';
}
