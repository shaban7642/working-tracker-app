class ProjectQueries {
  static const String getProjects = r'''
    query Project_GetProjects(
      $filter: ProjectFilterInput
      $pagination: PaginationInput
      $orderBy: ProjectOrderByInput
      $includeFilterOptions: Boolean
    ) {
      Project_Project_GetProjects(
        filter: $filter
        pagination: $pagination
        orderBy: $orderBy
        includeFilterOptions: $includeFilterOptions
      ) {
        items {
          id
          name
          description
          imageUrl
          imageThumbnailUrl
          isActive
          boardMemberCount
          employeeCount
          childCount
          createdAt
          updatedAt
          category {
            id
            name
            code
          }
          categoryId
          address {
            id
            district
            city
            state
            country
            street
            latitude
            longitude
          }
          addressId
          parent {
            id
            name
          }
          parentId
          company {
            id
            name
          }
          companyId
          createdBy {
            id
            firstName
            lastName
          }
          createdById
        }
        hasNextPage
        hasPreviousPage
        page
        pageSize
        total
        totalPages
        filterOptions {
          categories {
            id
            name
            code
            count
          }
          districts {
            name
            count
          }
        }
      }
    }
  ''';
}
