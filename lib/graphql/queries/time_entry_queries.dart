class TimeEntryQueries {
  static const String getMyPendingEntries = r'''
    query Attendance_TimeEntry_GetMyPendingEntries($pagination: PaginationInput) {
      Attendance_TimeEntry_GetMyPendingEntries(pagination: $pagination) {
        entries {
          id
          description
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
          tasks {
            id
            title
            description
            images {
              id
              imageUrl { url cacheKey }
            }
            createdAt
            updatedAt
          }
          createdAt
          updatedAt
        }
        totalCount
      }
    }
  ''';

  static const String updateTimeEntry = r'''
    mutation Attendance_TimeEntry_Update($input: UpdateTimeEntryInput!, $timeEntryId: String!) {
      Attendance_TimeEntry_Update(input: $input, timeEntryId: $timeEntryId) {
        createdAt
        description
        duration
        employee {
          email
          firstName
          id
          lastName
        }
        employeeId
        endTime
        id
        status
        taskSubmissionStatus
        project {
          description
          id
          name
        }
        projectId
        session {
          id
        }
        sessionId
        startTime
        tasks {
          description
          id
          title
        }
        updatedAt
      }
    }
  ''';

  static const String pauseTimeEntry = r'''
    mutation Attendance_TimeEntry_Pause($timeEntryId: String!) {
      Attendance_TimeEntry_Pause(timeEntryId: $timeEntryId) {
        createdAt
        description
        duration
        employeeId
        endTime
        id
        status
        taskSubmissionStatus
        project {
          description
          id
          name
        }
        projectId
        sessionId
        startTime
        updatedAt
      }
    }
  ''';

  static const String resumeTimeEntry = r'''
    mutation Attendance_TimeEntry_Resume($timeEntryId: String!) {
      Attendance_TimeEntry_Resume(timeEntryId: $timeEntryId) {
        createdAt
        description
        duration
        employeeId
        endTime
        id
        status
        taskSubmissionStatus
        project {
          description
          id
          name
        }
        projectId
        sessionId
        startTime
        updatedAt
      }
    }
  ''';

  static const String setProject = r'''
    mutation Attendance_TimeEntry_SetProject($input: SetProjectTimeEntryInput!) {
      Attendance_TimeEntry_SetProject(input: $input) {
        createdAt
        description
        duration
        employeeId
        endTime
        id
        status
        taskSubmissionStatus
        project {
          id
          name
          imageUrl { url cacheKey }
        }
        projectId
        sessionId
        startTime
        updatedAt
      }
    }
  ''';

  static const String deleteTimeEntry = r'''
    mutation Attendance_TimeEntry_Delete($timeEntryId: String!) {
      Attendance_TimeEntry_Delete(timeEntryId: $timeEntryId)
    }
  ''';
}
