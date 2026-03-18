# Story 9.3: Add refreshEndpoint to AuthConfig

Status: backlog

## Story

As a developer,
I want to configure a refresh endpoint URL in AuthConfig,
so that ApiX can handle token refresh automatically.

## Acceptance Criteria

1. **Given** AuthConfig
   **When** I provide refreshEndpoint
   **Then** it's stored as relative URL to baseUrl

2. **Given** AuthConfig with refreshEndpoint
   **When** I also provide refreshHeaders
   **Then** custom headers are used for refresh request

3. **Given** AuthConfig with refreshEndpoint
   **When** I provide onTokenRefreshed callback
   **Then** it receives raw Response after successful refresh

4. **Given** existing AuthConfig users
   **When** they don't use new fields
   **Then** everything works as before (backward compatible)

## Tasks / Subtasks

- [ ] Task 1: Update AuthConfig class
  - [ ] Add refreshEndpoint (String?) - relative URL
  - [ ] Add refreshHeaders (Map<String, String>?) - optional custom headers
  - [ ] Add onTokenRefreshed (Future<void> Function(Response)?) - callback
  - [ ] Add refreshTokenBodyKey (String) - default: 'refresh_token'
  - [ ] Update copyWith() method
  - [ ] Keep onRefresh for backward compatibility

- [ ] Task 2: Add Response type callback
  - [ ] Import dio Response type
  - [ ] Define OnTokenRefreshedCallback typedef

- [ ] Task 3: Write unit tests
  - [ ] Test new fields default to null
  - [ ] Test copyWith with new fields
  - [ ] Test backward compatibility with existing onRefresh

## Dev Notes

### Implementation Pattern

```dart
/// Callback invoked after successful token refresh with raw response.
typedef OnTokenRefreshedCallback = Future<void> Function(Response response);

class AuthConfig {
  // Existing fields...
  
  /// Endpoint for token refresh (relative to baseUrl).
  /// If provided, ApiX handles the refresh HTTP call.
  final String? refreshEndpoint;

  /// Optional headers to include in refresh request.
  final Map<String, String>? refreshHeaders;

  /// Callback invoked with raw Response after successful refresh.
  /// Developer parses response and calls tokenProvider.saveTokens().
  final OnTokenRefreshedCallback? onTokenRefreshed;

  /// Key name for refresh token in request body.
  /// Defaults to 'refresh_token'.
  final String refreshTokenBodyKey;

  const AuthConfig({
    required this.tokenProvider,
    this.onRefresh, // Keep for backward compatibility
    this.refreshEndpoint,
    this.refreshHeaders,
    this.onTokenRefreshed,
    this.refreshTokenBodyKey = 'refresh_token',
    // ... existing fields
  });
}
```

### References

- [PRD: FR48-FR49, FR51]
- [Product Brief: SecureTokenProvider]

## Dev Agent Record

### File List (Target)

- `lib/src/auth/auth_config.dart` - Updated AuthConfig
- `test/auth/auth_config_test.dart` - Updated tests
