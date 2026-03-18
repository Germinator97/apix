---
stepsCompleted: ['step-01-validate-prerequisites', 'step-02-design-epics', 'step-03-create-stories', 'step-04-final-validation']
status: complete
inputDocuments: ['prd.md', 'architecture.md']
---

# apix - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for apix, decomposing the requirements from the PRD and Architecture into implementable stories.

## Requirements Inventory

### Functional Requirements

- FR1: Developer can create an ApiClient with minimal configuration (baseUrl only)
- FR2: Developer can customize timeout settings per ApiClient instance
- FR3: Developer can provide custom interceptors to extend functionality
- FR4: Developer can change configuration at runtime
- FR5: Developer can provide a TokenProvider for authentication
- FR6: System can automatically attach auth tokens to requests
- FR7: System can detect 401 responses and trigger token refresh
- FR8: System can queue concurrent requests during token refresh
- FR9: System can retry queued requests after successful refresh
- FR10: Developer can customize refresh behavior via AuthConfig
- FR11: System can automatically retry failed requests
- FR12: Developer can configure retry attempts and delays
- FR13: Developer can specify which HTTP status codes trigger retry
- FR14: System can apply exponential backoff between retries
- FR15: Developer can disable retry for specific requests
- FR16: Developer can mark endpoints as cacheable via annotations
- FR17: System can store responses in cache storage
- FR18: Developer can choose cache strategy (CacheFirst, NetworkFirst, HttpCacheAware)
- FR19: System can deduplicate identical concurrent requests
- FR20: Developer can provide custom CacheStorage implementation
- FR21: Developer can invalidate cache programmatically
- FR22: System can map HTTP errors to typed exceptions
- FR23: System can map network errors to typed exceptions
- FR24: Developer can catch specific exception types
- FR25: System can provide detailed error information (status, message, body)
- FR26: Developer can make GET, POST, PUT, DELETE, PATCH requests
- FR27: Developer can send JSON body with requests
- FR28: Developer can send multipart/form-data requests
- FR29: System can deserialize JSON responses to Dart objects (optional, raw JSON accessible)
- FR30: Developer can access raw response when needed
- FR31: System can log requests and responses in dev mode
- FR32: Developer can enable/disable logging
- FR33: Developer can provide custom log handler
- FR34: Developer can provide custom error reporter for external monitoring
- FR35: System can expose request context (breadcrumbs) to error reporters
- FR36: Developer can track request/response metrics (timing, status)
- FR37: System can report errors with full context (request, response, stack)
- FR38: Developer can create custom interceptors for monitoring (Sentry, Firebase, etc.)
- FR39: Developer can use `.getResult()` for functional Result<T,E> pattern instead of exceptions
- FR40: System provides built-in SentryInterceptor with SentryConfig (dsn, environment, enabled)
- FR41: Developer can enable/disable Sentry reporting per environment
- FR42: System automatically captures API errors to Sentry with request context
- FR43: Developer can use SecureStorageService for secure key-value storage
- FR44: SecureStorageService provides write(key, value), read(key), delete(key), deleteAll() methods
- FR45: Developer can use SecureTokenProvider as ready-to-use TokenProvider implementation
- FR46: SecureTokenProvider uses SecureStorageService via composition
- FR47: Developer can inject custom SecureStorageService into SecureTokenProvider
- FR48: Developer can configure refreshEndpoint (relative URL) in AuthConfig
- FR49: Developer can provide optional refreshHeaders for custom headers during refresh
- FR50: System calls refreshEndpoint automatically when token refresh is triggered
- FR51: System invokes onTokenRefreshed(Response) callback with raw response
- FR52: Developer parses response and saves tokens (same pattern as login)
- FR53: SecureStorageService can be used independently for other secrets (Firebase Auth, API keys)

### NonFunctional Requirements

- NFR1: Package overhead < 5ms par requete
- NFR2: Zero memory leaks sur usage prolonge
- NFR3: Pas de blocage du main thread (async pur)
- NFR4: Test coverage > 90%
- NFR5: Zero bugs critiques en production pendant 30 jours = stable
- NFR6: Gestion gracieuse de tous les edge cases reseau
- NFR7: Compatible Dio ^5.0.0
- NFR8: Compatible Flutter >= 3.10.0, Dart >= 3.0.0
- NFR9: Fonctionne sur toutes les platforms (iOS, Android, Web, Desktop)
- NFR10: Pas de dependances natives requises
- NFR11: Code conforme aux Effective Dart guidelines
- NFR12: 100% API publique documentee
- NFR13: Semantic versioning strict (pas de breaking changes en minor)
- NFR14: CHANGELOG maintenu a jour
- NFR15: Tests d'integration avec mock server pour edge cases reseau
- NFR16: Tests de regression automatises sur CI pour chaque PR

### Additional Requirements

From Architecture:
- Starter Template: `flutter create --template=package --project-name=apix .`
- GitHub Actions CI: analyze, format, test, pana
- Makefile for standardized commands
- 8 ADRs to implement (ADR-001 to ADR-008)
- Barrel exports pattern for lib/apix.dart
- Test structure mirroring lib/src/

### UX Design Requirements

N/A - Package infrastructure, no UI

### FR Coverage Map

| FR | Epic | Description |
|----|------|-------------|
| FR1-FR4 | Epic 3 | Client configuration |
| FR5-FR10 | Epic 4 | Authentication |
| FR11-FR15 | Epic 5 | Retry logic |
| FR16-FR21 | Epic 6 | Caching |
| FR22-FR25, FR39 | Epic 2 | Error handling |
| FR26-FR30 | Epic 3 | Request/Response |
| FR31-FR33 | Epic 7 | Logging |
| FR34-FR42 | Epic 7 | Observability |
| FR43-FR53 | Epic 9 | Secure Token Storage |

## Epic List

### Epic 1: Project Foundation
Le projet est initialisé avec la structure, CI et tooling de base.
**FRs covered:** Setup (starter template, CI, Makefile)
**Depends on:** —

### Epic 2: Error Hierarchy
Le développeur peut gérer les erreurs de manière granulaire avec exceptions typées.
**FRs covered:** FR22, FR23, FR24, FR25, FR39
**Depends on:** Epic 1

### Epic 3: Core API Client
Le développeur peut faire des requêtes API de base avec configuration flexible.
**FRs covered:** FR1, FR2, FR3, FR4, FR26, FR27, FR28, FR29, FR30
**Depends on:** Epic 2

### Epic 4: Authentication & Refresh
Le développeur peut gérer l'authentification avec refresh token queue automatique.
**FRs covered:** FR5, FR6, FR7, FR8, FR9, FR10
**Depends on:** Epic 2, Epic 3

### Epic 5: Retry Logic
Le système retry automatiquement les requêtes échouées avec backoff exponentiel.
**FRs covered:** FR11, FR12, FR13, FR14, FR15
**Depends on:** Epic 2, Epic 3

### Epic 6: Caching
Le développeur peut cacher les réponses avec différentes stratégies.
**FRs covered:** FR16, FR17, FR18, FR19, FR20, FR21
**Depends on:** Epic 3

### Epic 7: Logging & Observability
Le développeur peut logger et monitorer les requêtes avec Sentry built-in.
**FRs covered:** FR31, FR32, FR33, FR34, FR35, FR36, FR37, FR38, FR40, FR41, FR42
**Depends on:** Epic 3

### Epic 8: Documentation & Release
Le package est prêt pour publication sur pub.dev avec 160/160 points.
**FRs covered:** NFR11, NFR12, NFR13, NFR14
**Depends on:** All

### Epic 9: Secure Token Storage (v0.3)
Le développeur peut utiliser SecureTokenProvider prêt à l'emploi avec refresh simplifié.
**FRs covered:** FR43, FR44, FR45, FR46, FR47, FR48, FR49, FR50, FR51, FR52, FR53
**Depends on:** Epic 4

---

## Epic 1: Project Foundation

Le projet est initialisé avec la structure, CI et tooling de base.

### Story 1.1: Initialize Package Structure

As a developer,
I want to create the apix package with standard Flutter structure,
So that I have a solid foundation to build upon.

**Acceptance Criteria:**

**Given** the project directory is empty
**When** I run `flutter create --template=package --project-name=apix .`
**Then** the package structure is created with lib/, test/, pubspec.yaml
**And** analysis_options.yaml is configured with recommended lints

### Story 1.2: Setup GitHub Actions CI

As a maintainer,
I want CI to run on every PR,
So that code quality is enforced automatically.

**Acceptance Criteria:**

**Given** a PR is opened
**When** GitHub Actions runs
**Then** `dart analyze --fatal-infos` passes
**And** `dart format --set-exit-if-changed .` passes
**And** `flutter test --coverage` runs
**And** coverage report is generated

### Story 1.3: Create Makefile & Dev Tooling

As a developer,
I want standardized commands via Makefile,
So that all contributors use the same workflow.

**Acceptance Criteria:**

**Given** the Makefile exists
**When** I run `make test`
**Then** all tests execute
**When** I run `make analyze`
**Then** dart analyze and format check run
**When** I run `make coverage`
**Then** coverage report is generated

---

## Epic 2: Error Hierarchy

Le développeur peut gérer les erreurs de manière granulaire avec exceptions typées.

### Story 2.1: Create Base ApiException

As a developer,
I want a base ApiException class,
So that all API errors have a common type to catch.

**Acceptance Criteria:**

**Given** an API error occurs
**When** I catch ApiException
**Then** I have access to message, statusCode, and originalError
**And** the exception provides a clear toString() representation

### Story 2.2: Create Network Exception Hierarchy

As a developer,
I want typed network exceptions (Timeout, Connection),
So that I can handle network issues specifically.

**Acceptance Criteria:**

**Given** a request timeout occurs
**When** the error is mapped
**Then** TimeoutException is thrown
**And** it extends NetworkException which extends ApiException

**Given** a connection failure occurs
**When** the error is mapped
**Then** ConnectionException is thrown

### Story 2.3: Create HTTP Exception Hierarchy

As a developer,
I want typed HTTP exceptions (Client 4xx, Server 5xx),
So that I can handle HTTP errors granularly.

**Acceptance Criteria:**

**Given** a 4xx HTTP response is received
**When** the error is mapped
**Then** ClientException is thrown (UnauthorizedException for 401, ForbiddenException for 403)

**Given** a 5xx HTTP response is received
**When** the error is mapped
**Then** ServerException is thrown
**And** both extend HttpException which extends ApiException

### Story 2.4: Implement Result Pattern

As a developer,
I want .getResult() extension for functional error handling,
So that I can use Result pattern instead of exceptions.

**Acceptance Criteria:**

**Given** any Future<T> that may throw ApiException
**When** I call .getResult()
**Then** I get Future<Result<T, ApiException>>
**And** I can use isSuccess/isFailure to check state
**And** I can use fold() or when() for pattern matching

---

## Epic 3: Core API Client

Le développeur peut faire des requêtes API de base avec configuration flexible.

### Story 3.1: Create ApiClient with Minimal Config

As a developer,
I want to create an ApiClient with just a baseUrl,
So that I can start making requests immediately.

**Acceptance Criteria:**

**Given** I instantiate ApiClient(baseUrl: 'https://api.example.com')
**Then** the client is ready to use with sensible defaults
**And** timeout defaults to 30 seconds
**And** I can optionally provide custom timeout, headers, interceptors

### Story 3.2: Implement HTTP Methods

As a developer,
I want to make GET, POST, PUT, DELETE, PATCH requests,
So that I can interact with any REST API.

**Acceptance Criteria:**

**Given** an ApiClient instance
**When** I call client.get('/path')
**Then** a GET request is sent
**And** POST, PUT, DELETE, PATCH methods work similarly
**And** I can pass headers, queryParams, body as needed

### Story 3.3: Handle JSON Requests & Responses

As a developer,
I want to send JSON body and receive JSON responses,
So that I can work with standard API formats.

**Acceptance Criteria:**

**Given** a POST request with Map<String, dynamic> body
**When** I send the request
**Then** Content-Type is set to application/json by default (via MultipartInterceptor)
**And** response JSON is accessible as Map
**And** I can optionally deserialize to a model via `*AndDecode` methods
**And** I can configure defaultContentType globally or override per-request

**Implementation (ADR-010):**
- JSON is the default Content-Type (configurable via `defaultContentType`)
- No separate `postJson()`, `putJson()` methods - use standard `post()`, `put()`
- `getAndDecode()`, `postAndDecode()`, `getListAndDecode()` for typed deserialization

### Story 3.4: Support Multipart Requests

As a developer,
I want to send multipart/form-data requests,
So that I can upload files.

**Acceptance Criteria:**

**Given** a file to upload
**When** I call client.post with File in data Map
**Then** MultipartInterceptor auto-detects the File
**And** Converts to FormData automatically
**And** Sets Content-Type to multipart/form-data

**Implementation (ADR-009):**
- No separate `postMultipart()`, `uploadFile()` methods
- Just pass `File` or `List<File>` in your data Map
- MultipartInterceptor handles detection and conversion transparently

### Story 3.5: Provide Raw Response Access

As a developer,
I want to access the raw Dio Response when needed,
So that I can handle special cases.

**Acceptance Criteria:**

**Given** any request
**When** I need raw response
**Then** I can access statusCode, headers, data directly
**And** this works for all HTTP methods

---

## Epic 4: Authentication & Refresh

Le développeur peut gérer l'authentification avec refresh token queue automatique.

### Story 4.1: Create TokenProvider Interface

As a developer,
I want to implement a TokenProvider interface,
So that apix can manage my tokens.

**Acceptance Criteria:**

**Given** I need to provide token management
**When** I implement TokenProvider
**Then** I provide getAccessToken(), getRefreshToken(), saveTokens(), clearTokens()
**And** all methods are async for secure storage compatibility

### Story 4.2: Implement AuthInterceptor

As a developer,
I want auth tokens attached automatically to requests,
So that I don't manage headers manually.

**Acceptance Criteria:**

**Given** a TokenProvider is configured via AuthConfig
**When** I make a request
**Then** Authorization header is added with Bearer token
**And** I can customize header name via AuthConfig

### Story 4.3: Implement Configurable Refresh Detection

As a developer,
I want automatic token refresh on configurable status codes,
So that users stay logged in seamlessly.

**Acceptance Criteria:**

**Given** refreshStatusCodes is configured (default: [401])
**When** a response matches one of these codes
**Then** refresh is triggered via TokenProvider
**And** original request is retried with new token
**And** I can configure [401, 403] or other codes via AuthConfig

### Story 4.4: Implement Refresh Token Queue

As a developer,
I want concurrent requests queued during refresh,
So that no race conditions occur.

**Acceptance Criteria:**

**Given** multiple concurrent requests receive a refresh-triggering status code
**When** refresh is in progress
**Then** all requests wait in queue (Completer pattern)
**And** after refresh succeeds, all queued requests retry
**And** if refresh fails, all queued requests fail with AuthException

---

## Epic 5: Retry Logic

Le système retry automatiquement les requêtes échouées avec backoff exponentiel.

### Story 5.1: Implement RetryInterceptor

As a developer,
I want failed requests to retry automatically,
So that transient failures are handled transparently.

**Acceptance Criteria:**

**Given** RetryConfig is provided
**When** a retryable error occurs
**Then** the request is retried up to maxAttempts times
**And** default maxAttempts is 3

### Story 5.2: Configure Retry Status Codes

As a developer,
I want to specify which HTTP codes trigger retry,
So that I control retry behavior.

**Acceptance Criteria:**

**Given** retryStatusCodes is configured (default: [500, 502, 503, 504])
**When** response matches these codes
**Then** retry is triggered
**And** I can customize the list via RetryConfig

### Story 5.3: Implement Exponential Backoff

As a developer,
I want exponential backoff between retries,
So that I don't overwhelm failing servers.

**Acceptance Criteria:**

**Given** retry is triggered
**When** waiting between attempts
**Then** delay follows exponential backoff (e.g., 1s, 2s, 4s)
**And** I can configure base delay and multiplier

### Story 5.4: Disable Retry Per Request

As a developer,
I want to disable retry for specific requests,
So that I control critical operations.

**Acceptance Criteria:**

**Given** a request with noRetry option
**When** an error occurs
**Then** no retry is attempted
**And** the error is thrown immediately

---

## Epic 6: Caching

Le développeur peut cacher les réponses avec différentes stratégies.

### Story 6.1: Create CacheStorage Interface

As a developer,
I want a CacheStorage abstraction,
So that I can use any storage backend.

**Acceptance Criteria:**

**Given** CacheStorage interface
**Then** it provides get(), set(), remove(), clear() methods
**And** SharedPreferences implementation is provided by default
**And** I can provide custom implementation via CacheConfig

### Story 6.2: Implement CacheFirst & NetworkFirst

As a developer,
I want basic cache strategies,
So that I control freshness vs speed tradeoffs.

**Acceptance Criteria:**

**Given** CacheConfig with strategy CacheFirst
**When** cache exists
**Then** return cached response immediately

**Given** CacheConfig with strategy NetworkFirst
**When** network succeeds
**Then** return network response and update cache
**And** fallback to cache if network fails

### Story 6.3: Implement HttpCacheAware Strategy

As a developer,
I want to respect HTTP cache headers,
So that I follow standard caching semantics.

**Acceptance Criteria:**

**Given** HttpCacheAware strategy
**When** response has Cache-Control header
**Then** respect max-age, no-cache, no-store directives
**And** support ETag with If-None-Match
**And** handle 304 Not Modified responses
**And** fallback to our cache if no HTTP headers present

### Story 6.4: Implement Request Deduplication

As a developer,
I want identical concurrent requests deduplicated,
So that I don't waste bandwidth.

**Acceptance Criteria:**

**Given** multiple identical GET requests in flight
**When** they hit the cache interceptor
**Then** only one network request is made
**And** all callers receive the same response
**And** deduplication based on URL + method + body hash
**And** if original request fails, all waiters receive the error

### Story 6.5: Implement Cache Invalidation

As a developer,
I want to invalidate cache programmatically,
So that I can force fresh data.

**Acceptance Criteria:**

**Given** cached data exists
**When** I call client.invalidateCache(key) or client.clearCache()
**Then** the specified cache entries are removed
**And** next request fetches fresh data

---

## Epic 7: Logging & Observability

Le développeur peut logger et monitorer les requêtes avec Sentry built-in.

### Story 7.1: Implement LoggerInterceptor

As a developer,
I want requests/responses logged in dev mode,
So that I can debug API calls easily.

**Acceptance Criteria:**

**Given** LoggerConfig is enabled
**Then** requests log method, URL, headers, body
**And** responses log status, duration, body
**And** logging is disabled by default in release mode

### Story 7.2: Custom Log Handler

As a developer,
I want to provide my own log handler,
So that I can integrate with my logging solution.

**Acceptance Criteria:**

**Given** custom logHandler in LoggerConfig
**Then** all logs go through my handler
**And** I receive structured log data (not just strings)

### Story 7.3: Implement SentryInterceptor

As a developer,
I want Sentry error reporting built-in,
So that I don't have to implement it myself.

**Acceptance Criteria:**

**Given** SentryConfig with dsn and environment
**Then** API errors are captured to Sentry
**And** request context (URL, method, headers) is included
**And** I can enable/disable per environment via enabled flag

### Story 7.4: Request Breadcrumbs & Metrics

As a developer,
I want request breadcrumbs and timing metrics,
So that I can track API performance.

**Acceptance Criteria:**

**Given** observability is enabled
**Then** each request creates a breadcrumb with timing
**And** I can track request/response metrics (duration, status)
**And** custom error reporters can access this context

---

## Epic 8: Documentation & Release

Le package est prêt pour publication sur pub.dev avec 160/160 points.

### Story 8.1: Create README & Getting Started

As a developer,
I want a clear README with examples,
So that I can start using apix quickly.

**Acceptance Criteria:**

**Given** the README.md
**Then** it includes installation instructions
**And** quick start example (5 lines to first request)
**And** links to full documentation
**And** badges (pub.dev, CI, coverage)

### Story 8.2: Document Public API

As a developer,
I want 100% documented public API,
So that I understand every class and method.

**Acceptance Criteria:**

**Given** any public class/method
**Then** it has dartdoc with description
**And** includes code examples where helpful
**And** dart doc generates without warnings

### Story 8.3: Create Example App

As a developer,
I want a working example app,
So that I can see apix in action.

**Acceptance Criteria:**

**Given** the example/ folder
**Then** it contains a runnable Flutter app
**And** demonstrates all major features (auth, retry, cache)
**And** includes comments explaining each feature

### Story 8.4: Prepare for pub.dev Release

As a maintainer,
I want 160/160 pub points,
So that the package is trusted.

**Acceptance Criteria:**

**Given** pana analysis
**Then** score is 160/160
**And** CHANGELOG.md is up to date
**And** LICENSE is present
**And** all platforms are supported

### Story 8.5: Create Integration Test Suite

As a maintainer,
I want integration tests for critical flows,
So that regressions are caught early.

**Acceptance Criteria:**

**Given** mock server setup
**Then** test full auth flow with refresh queue
**And** test retry with backoff
**And** test cache strategies (CacheFirst, NetworkFirst, HttpCacheAware)
**And** tests run on CI for every PR

---

## Epic 9: Secure Token Storage (v0.3)

Le développeur peut utiliser SecureTokenProvider prêt à l'emploi avec refresh simplifié.

### Story 9.1: Implement SecureStorageService

As a developer,
I want a SecureStorageService wrapper for flutter_secure_storage,
So that I can securely store key-value pairs without boilerplate.

**Acceptance Criteria:**

**Given** I need secure storage
**When** I create a SecureStorageService
**Then** I can use write(), read(), delete(), deleteAll() methods
**And** default FlutterSecureStorage uses AndroidOptions(encryptedSharedPreferences: true)
**And** I can inject my own FlutterSecureStorage instance

### Story 9.2: Implement SecureTokenProvider

As a developer,
I want a ready-to-use SecureTokenProvider implementation,
So that I don't have to implement TokenProvider manually.

**Acceptance Criteria:**

**Given** I need token management
**When** I create a SecureTokenProvider
**Then** it implements TokenProvider interface
**And** uses SecureStorageService via composition
**And** I can inject my own SecureStorageService
**And** I can configure custom storage keys
**And** storage is exposed for secondary usage (Firebase Auth, API keys)

### Story 9.3: Add refreshEndpoint to AuthConfig

As a developer,
I want to configure a refresh endpoint URL in AuthConfig,
So that ApiX can handle token refresh automatically.

**Acceptance Criteria:**

**Given** AuthConfig
**When** I provide refreshEndpoint
**Then** it's stored as relative URL to baseUrl
**And** I can provide optional refreshHeaders
**And** I can provide onTokenRefreshed callback receiving raw Response
**And** existing onRefresh callback still works (backward compatible)

### Story 9.4: Update AuthInterceptor for Simplified Refresh

As a developer,
I want AuthInterceptor to handle refresh calls automatically,
So that I only need to provide the endpoint URL.

**Acceptance Criteria:**

**Given** AuthConfig with refreshEndpoint
**When** a 401 is received
**Then** AuthInterceptor calls refreshEndpoint with refresh token
**And** onTokenRefreshed callback receives raw Response
**And** refreshHeaders are included if provided
**And** old onRefresh behavior is preserved (backward compatible)

### Story 9.5: Write Tests for Secure Token Storage

As a maintainer,
I want comprehensive tests for SecureTokenProvider feature,
So that the implementation is reliable and regression-free.

**Acceptance Criteria:**

**Given** all new classes
**Then** unit tests cover > 90% of code
**And** integration tests verify simplified refresh flow
**And** backward compatibility is tested

### Story 9.6: Update Documentation and Examples

As a developer,
I want clear documentation for SecureTokenProvider,
So that I can integrate it quickly.

**Acceptance Criteria:**

**Given** README.md
**Then** SecureTokenProvider section is added
**And** basic and advanced usage examples are provided
**And** example app uses SecureTokenProvider
**And** CHANGELOG documents v0.3.0 changes
