class TaskQueries {
  static const String createTask = r'''
    mutation Attendance_Task_Create($input: CreateTaskInput!) {
      Attendance_Task_Create(input: $input) {
        createdAt
        description
        id
        images {
          id
          imageUrl
        }
        timeEntry {
          description
          id
        }
        timeEntryId
        title
        updatedAt
      }
    }
  ''';

  static const String updateTask = r'''
    mutation Attendance_Task_Update($input: UpdateTaskInput!, $taskId: String!) {
      Attendance_Task_Update(input: $input, taskId: $taskId) {
        createdAt
        description
        id
        images {
          id
          imageUrl
        }
        timeEntry {
          description
          id
        }
        timeEntryId
        title
        updatedAt
      }
    }
  ''';

  static const String deleteTask = r'''
    mutation Attendance_Task_Delete($taskId: String!) {
      Attendance_Task_Delete(taskId: $taskId)
    }
  ''';

  static const String getByTimeEntry = r'''
    query Attendance_Task_GetByTimeEntry($timeEntryId: String!) {
      Attendance_Task_GetByTimeEntry(timeEntryId: $timeEntryId) {
        createdAt
        description
        id
        images {
          id
          imageUrl
        }
        timeEntry {
          description
          id
        }
        timeEntryId
        title
        updatedAt
      }
    }
  ''';

  static const String addTaskImage = r'''
    mutation Attendance_TaskImage_Add($input: AddTaskImageInput!) {
      Attendance_TaskImage_Add(input: $input) {
        caption
        createdAt
        fileSize
        id
        imageUrl
        mimeType
        order
        task {
          description
          id
          title
        }
        taskId
        thumbnailUrl
      }
    }
  ''';

  static const String removeTaskImage = r'''
    mutation Attendance_TaskImage_Remove($imageId: String!) {
      Attendance_TaskImage_Remove(imageId: $imageId)
    }
  ''';
}
