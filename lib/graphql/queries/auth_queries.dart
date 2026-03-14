class AuthQueries {
  static const String initiateSsoLogin = r'''
    mutation Auth_Sso_InitiateSsoLogin($input: InitiateSsoInput) {
      Auth_Sso_InitiateSsoLogin(input: $input) {
        authUrl
        state
      }
    }
  ''';

  static const String verifySsoCallback = r'''
    mutation Auth_Sso_VerifySsoCallback($input: SsoCallbackInput!) {
      Auth_Sso_VerifySsoCallback(input: $input) {
        message
        success
        tokens {
          accessExpiresAt
          accessToken
          refreshExpiresAt
          refreshToken
        }
      }
    }
  ''';

  static const String devLogin = r'''
    mutation Auth_DevAuth_DevLogin($input: DevLoginInput!) {
      Auth_DevAuth_DevLogin(input: $input) {
        message
        success
        tokens {
          accessExpiresAt
          accessToken
          refreshExpiresAt
          refreshToken
        }
      }
    }
  ''';

  static const String refreshTokens = r'''
    mutation Auth_Session_RefreshTokens($input: RefreshTokenInput!) {
      Auth_Session_RefreshTokens(input: $input) {
        accessExpiresAt
        accessToken
        refreshExpiresAt
        refreshToken
      }
    }
  ''';

  static const String logout = r'''
    mutation Auth_Session_Logout {
      Auth_Session_Logout
    }
  ''';

  static const String getMyProfile = r'''
    query Employee_GetMyProfile {
      Employee_GetMyProfile {
        address {
          id
        }
        addressId
        company {
          email
          id
          name
          standardWorkingHours
        }
        companyId
        contractEndDate
        createdAt
        dateJoined
        dateOfBirth
        department {
          description
          id
          name
        }
        departmentId
        designation
        email
        employeeCode
        firstName
        fullName
        grade
        id
        isActive
        isSuperAdmin
        lastName
        lineManager {
          email
          firstName
          id
          lastName
        }
        lineManagerId
        nationality
        phone
        professionalImageUrl
        profileCompleteness
        team {
          description
          id
          name
        }
        teamId
        updatedAt
      }
    }
  ''';

  static const String getMyPermissions = r'''
    query Permission_EmployeePermission_GetMyPermissions {
      Permission_EmployeePermission_GetMyPermissions {
        permission {
          id
          code
          name
          description
          module
        }
        scope {
          id
          code
          name
          description
        }
        scopeCode
        source
        assignedViaGroupId
      }
    }
  ''';
}
