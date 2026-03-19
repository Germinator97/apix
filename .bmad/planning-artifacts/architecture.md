---
stepsCompleted: ['step-01-init', 'step-02-context', 'step-03-starter', 'step-04-decisions', 'step-05-patterns', 'step-06-structure', 'step-07-validation', 'step-08-complete']
status: complete
inputDocuments: ['prd.md', 'product-brief-apix-2026-03-16.md', 'brainstorming-session-2026-03-15-2311.md']
workflowType: 'architecture'
project_name: 'apix'
user_name: 'Germinator'
date: '2026-03-16'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**
39 FRs couvrant un pipeline API complet :
- Client configuration et lifecycle (FR1-FR4)
- Authentication avec refresh token queue (FR5-FR10)
- Retry logic avec backoff exponentiel (FR11-FR15)
- Cache multi-strategie (FR16-FR21)
- Error handling avec exceptions typees + Result optionnel (FR22-FR25, FR39)
- Observability et monitoring extensible (FR34-FR38)
- Sentry Integration (FR40-FR42)

**Non-Functional Requirements:**
16 NFRs imposant :
- Performance : < 5ms overhead, zero memory leaks
- Reliability : 90%+ coverage, zero breaking changes minor
- Integration : Dio 5.x, Flutter 3.10+, toutes platforms
- Maintainability : Effective Dart, API 100% documentee

**Scale & Complexity:**
- Primary domain: Flutter Infrastructure Package
- Complexity level: Medium-High
- Estimated architectural components: 8

### Technical Constraints & Dependencies

- **Transport** : Dio ^5.0.0 (pas d'abstraction multi-client)
- **Storage** : CacheStorage abstrait, SharedPrefs default
- **Platform** : iOS, Android, Web, macOS, Windows, Linux
- **Dart** : >= 3.0.0 avec full null safety
- **Interceptor Order** : Auth → Retry → Cache → Logger (ordre critique, inversion = bugs)

### Cross-Cutting Concerns Identified

1. **Async/Concurrency** — Refresh token queue, request deduplication
2. **Error Propagation** — Exceptions typees a travers toutes les couches
3. **Observability** — Logging, metrics, error reporting
4. **Configuration** — Overridable a tous les niveaux
5. **Time Control** — Retry backoff testable (clock injectable)
6. **Network Simulation** — Edge cases reseau testables

### Critical ADR Identified

**ADR-001: Refresh Token Queue Pattern**
- Pattern async avec Completer pour gerer requetes simultanees
- Doit gerer : timeout, retry apres succes, cleanup si echec
- Decision architecturale critique a documenter en priorite

## Starter Template Evaluation

### Primary Technology Domain

Flutter/Dart Infrastructure Package — destiné à être publié sur pub.dev

### Starter Options Considered

| Option | Avantages | Inconvénients |
|--------|-----------|---------------|
| `flutter create --template=package` | Officiel, standard, 160 pts ready | Structure basique |
| `very_good_cli` | Best practices VGV | Dépendance externe |
| `mason` custom | Contrôle total | Maintenance du template |

### Selected Starter: flutter create --template=package

**Rationale:**
- Template officiel = compatibilité garantie
- Structure reconnue par pub.dev scoring
- Pas de dépendances tooling supplémentaires
- Facile à étendre selon nos besoins

**Initialization Command:**

```bash
flutter create --template=package --project-name=apix .
```

### Architectural Decisions Provided by Starter

- **Language & Runtime:** Dart 3.x avec null safety
- **Project Structure:** lib/, test/, standard pub.dev
- **Analysis:** analysis_options.yaml (lints recommandés)
- **Testing:** package:test setup de base

### Customizations Required

**Structure lib/src/ avec barrel exports:**
```dart
// lib/apix.dart - barrel export
export 'src/client/api_client.dart';
export 'src/errors/api_exception.dart';
export 'src/interceptors/auth_interceptor.dart';
// etc.
```

**Makefile pour standardiser les commandes:**
- `make test` → run tests
- `make analyze` → dart analyze + format check
- `make coverage` → coverage report

**GitHub Actions CI:**
- analyze : `dart analyze --fatal-infos`
- format : `dart format --set-exit-if-changed .`
- test : `flutter test --coverage`
- pub points : `pana` pour vérifier le score

**Dependencies de test:**
- `mocktail` pour les mocks

## Core Architectural Decisions

### ADR-002: API Design - Direct Constructor with Optional Configs

**Decision:** Utiliser un constructeur direct avec configs optionnels et defaults sensés.

```dart
final client = ApiClient(
  baseUrl: 'https://api.example.com',
  authConfig: AuthConfig(tokenProvider: myTokenProvider),  // optional
  retryConfig: RetryConfig(maxAttempts: 3),                // optional
  cacheConfig: CacheConfig(strategy: CacheStrategy.networkFirst), // optional
);
```

**Rationale:** Simple pour démarrer, tout personnalisable pour les cas avancés.

### ADR-003: Interceptor Architecture - Hybrid Approach

**Decision:** Utiliser les Dio Interceptors natifs + interface pour custom interceptors.

```dart
abstract class ApixInterceptor {
  void onRequest(RequestOptions options);
  void onResponse(Response response);
  void onError(DioException error);
}
```

**Rationale:** Compatible avec l'écosystème Dio, extensible pour cas custom.

### ADR-004: Error Hierarchy - Hierarchical Exceptions

**Decision:** Hiérarchie d'exceptions granulaire.

```dart
ApiException (base)
├── NetworkException
│   ├── TimeoutException
│   └── ConnectionException
├── HttpException
│   ├── ClientException (4xx)
│   └── ServerException (5xx)
└── AuthException
    ├── UnauthorizedException (401)
    └── ForbiddenException (403)
```

**Rationale:** Permet un catch granulaire ou générique selon le besoin.

### ADR-005: Cache Strategy - Strategy Pattern

**Decision:** Implémenter les stratégies de cache avec le Strategy Pattern.

```dart
abstract class CacheStrategy {
  Future<Response?> handle(Request request, CacheStorage storage);
}

class CacheFirst implements CacheStrategy { ... }
class NetworkFirst implements CacheStrategy { ... }
class HttpCacheAware implements CacheStrategy { ... }
```

**Rationale:** Extensible, testable, respecte Open/Closed principle.

### ADR-006: Result Pattern - Extension Method

**Decision:** Implémenter `.getResult()` comme extension method.

```dart
extension ResultExtension<T> on Future<T> {
  Future<Result<T, ApiException>> getResult() async {
    try {
      return Result.success(await this);
    } on ApiException catch (e) {
      return Result.failure(e);
    }
  }
}
```

**Rationale:** Flexible, fonctionne sur toutes les requêtes sans modifier ApiClient.

### ADR-007: TokenProvider - Async Interface

**Decision:** Interface async pour compatibilité avec secure storage.

```dart
abstract class TokenProvider {
  Future<String?> getAccessToken();
  Future<String?> getRefreshToken();
  Future<void> saveTokens(String access, String refresh);
  Future<void> clearTokens();
}
```

**Rationale:** Compatible avec flutter_secure_storage et autres storages async.

### ADR-008: Sentry Built-in Integration

**Decision:** Fournir ErrorTrackingInterceptor et ErrorTrackingConfig comme built-in, pas juste custom.

```dart
final client = ApiClient(
  baseUrl: 'https://api.example.com',
  errorTrackingConfig: ErrorTrackingConfig(
    environment: 'production',
    onError: (e, {stackTrace, extra, tags}) async {
      await Sentry.captureException(e, stackTrace: stackTrace);
    },
  ),
);
```

**Rationale:** 
- Sentry est le standard pour le monitoring Flutter
- Config simple = adoption plus facile
- Désactivable par environnement (dev vs prod)
- Breadcrumbs et contexte request automatiques

### ADR-009: MultipartInterceptor - Auto-detection File → FormData

**Decision:** Créer un intercepteur interne qui détecte automatiquement les `File` dans les données et les convertit en `FormData`.

```dart
// L'utilisateur envoie simplement un File dans son Map
await client.post('/upload', data: {
  'file': File('/path/to/image.jpg'),
  'name': 'my-image',
});
// → L'intercepteur détecte File, convertit en FormData, set Content-Type: multipart/form-data
```

**Comportement:**
- Détecte `File`, `List<File>`, `Map<String, File>` dans les données
- Convertit automatiquement en `FormData` avec `MultipartFile`
- Set `Content-Type: multipart/form-data` automatiquement
- Si pas de fichiers, applique le `defaultContentType` (JSON par défaut)

**Rationale:**
- Pas de méthodes séparées `postMultipart()`, `uploadFile()` - API simplifiée
- L'utilisateur n'a pas à connaître les détails de FormData
- Détection transparente, comportement prévisible

### ADR-010: Default Content-Type JSON (Configurable)

**Decision:** `application/json` est le Content-Type par défaut, configurable globalement.

```dart
// JSON par défaut - rien à faire
await client.post('/users', data: {'name': 'John'});  // → application/json

// Override global
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  defaultContentType: 'text/xml',  // ou null pour désactiver
);

// Override par requête
await client.post('/data', data: body, options: Options(contentType: 'text/plain'));
```

**Rationale:**
- 99% des APIs REST modernes utilisent JSON
- Pas besoin de méthodes `postJson()`, `putJson()` - redondantes
- L'utilisateur configure uniquement s'il veut autre chose

### ADR-011: ApiClientFactory Pattern

**Decision:** Séparer la création de `ApiClient` dans une classe factory dédiée.

```dart
// Factory (recommandé)
final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  connectTimeout: Duration(seconds: 60),
);

// Via config
final client = ApiClientFactory.fromConfig(config);

// Direct (pour tests avec mock Dio)
final client = ApiClient(mockDio, config);
```

**Rationale:**
- Séparation des responsabilités (création vs utilisation)
- ApiClient reste simple (juste les méthodes HTTP)
- Facilite les tests (injection de mock Dio)
- Factory gère toute la configuration (interceptors, adapters, etc.)

### ADR-012: Optional HttpClientAdapter

**Decision:** Permettre un `HttpClientAdapter` personnalisé, optionnel.

```dart
// Par défaut - Dio utilise son adapter natif (fonctionne sur toutes plateformes)
final client = ApiClientFactory.create(baseUrl: 'https://api.example.com');

// Avec adapter personnalisé (mobile/desktop uniquement)
import 'dart:io';
import 'package:dio/io.dart';

final client = ApiClientFactory.create(
  baseUrl: 'https://api.example.com',
  httpClientAdapter: IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true; // dev only
      return client;
    },
  ),
);
```

**Rationale:**
- Optionnel - si null, Dio utilise son adapter par défaut
- Permet certificats auto-signés, proxies, etc.
- L'utilisateur choisit l'adapter selon sa plateforme
- Pas de conditional imports complexes dans le package

## Implementation Patterns & Consistency Rules

### Naming Conventions

| Élément | Convention | Exemple |
|---------|------------|---------|
| **Classes** | UpperCamelCase | `ApiClient`, `AuthInterceptor` |
| **Fichiers** | snake_case | `api_client.dart`, `auth_interceptor.dart` |
| **Variables** | lowerCamelCase | `accessToken`, `maxRetries` |
| **Constantes** | lowerCamelCase | `defaultTimeout` |
| **Privés** | prefix `_` | `_refreshCompleter`, `_tokenQueue` |

### File Structure Pattern

```
lib/src/
├── client/
│   ├── api_client.dart
│   ├── api_client_config.dart
│   ├── api_client_factory.dart
│   └── multipart_interceptor.dart
├── interceptors/
│   ├── auth_interceptor.dart
│   ├── retry_interceptor.dart
│   ├── cache_interceptor.dart
│   └── logger_interceptor.dart
├── errors/
│   ├── api_exception.dart
│   ├── network_exception.dart
│   └── http_exception.dart
├── cache/
│   ├── cache_storage.dart
│   ├── cache_strategy.dart
│   └── shared_prefs_cache_storage.dart
├── models/
│   └── result.dart
└── utils/
    └── completer_queue.dart
```

### Documentation Pattern

```dart
/// Description courte en une ligne.
///
/// Description détaillée si nécessaire.
///
/// Example:
/// ```dart
/// final client = ApiClient(baseUrl: 'https://api.example.com');
/// ```
class ApiClient { ... }
```

### Test Structure Pattern

```
test/
├── client/
│   └── api_client_test.dart
├── interceptors/
│   ├── auth_interceptor_test.dart
│   └── retry_interceptor_test.dart
└── integration/
    └── full_flow_test.dart
```

**Convention:** `*_test.dart` dans structure miroir de `lib/src/`

### Enforcement Guidelines

**All implementations MUST:**
- Suivre Effective Dart guidelines
- Documenter toute API publique avec dartdoc
- Utiliser `flutter analyze` sans warnings
- Formater avec `dart format`

## Architecture Validation Results

### Coherence Validation ✅

**Decision Compatibility:** Toutes les décisions (Dio 5.x, Dart 3.x, Flutter 3.10+) sont compatibles.

**Pattern Consistency:** Naming conventions Dart standard, structure pub.dev conforme.

**Structure Alignment:** lib/src/ supporte tous les ADRs définis.

### Requirements Coverage ✅

| Category | FRs | ADR/Support |
|----------|-----|-------------|
| Client Config | FR1-FR4 | ADR-002 |
| Auth | FR5-FR10 | ADR-001, ADR-007 |
| Retry | FR11-FR15 | RetryInterceptor |
| Cache | FR16-FR21 | ADR-005 |
| Errors | FR22-FR25, FR39 | ADR-004, ADR-006 |
| Logging | FR31-FR33 | LoggerInterceptor |
| Observability | FR34-FR42 | ADR-008 |

### Implementation Readiness ✅

- 8 ADRs documentés avec code examples
- Versions spécifiées (Dio ^5.0.0, Dart >=3.0.0)
- Patterns complets (naming, structure, docs)
- Structure fichiers complète avec mapping FR

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION

**Confidence Level:** High

**Key Strengths:**
- Architecture en couches claire
- Refresh Token Queue bien documenté (ADR-001)
- Sentry built-in simplifie adoption
- Extensibilité via custom interceptors

**First Implementation Priority:**
```bash
flutter create --template=package --project-name=apix .
```
