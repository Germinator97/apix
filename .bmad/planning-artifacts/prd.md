---
stepsCompleted: ['step-01-init', 'step-02-discovery', 'step-02b-vision', 'step-02c-executive-summary', 'step-03-success', 'step-04-journeys', 'step-05-domain-skipped', 'step-06-innovation', 'step-07-project-type', 'step-08-scoping', 'step-09-functional', 'step-10-nonfunctional', 'step-11-polish', 'step-12-complete']
status: complete
inputDocuments: ['product-brief-apix-2026-03-16.md', 'brainstorming-session-2026-03-15-2311.md', 'product-brief-secure-token-provider-2026-03-18.md', 'brainstorming-session-2026-03-18-secure-token-provider.md']
workflowType: 'prd'
briefCount: 1
brainstormingCount: 1
researchCount: 0
projectDocsCount: 0
classification:
  projectType: Infrastructure Package
  domain: Developer Infrastructure
  complexity: Medium-High
  projectContext: greenfield
---

# Product Requirements Document - apix

**Author:** Germinator
**Date:** 2026-03-16

## Executive Summary

**apix** est un package Flutter d'infrastructure API qui elimine la reimplementation repetitive des patterns de communication reseau. Il fournit une solution batteries-included combinant authentification avec refresh token queue, retry intelligent, cache flexible et gestion d'erreurs typees.

**Pitch :** Ne reecris plus jamais ton client API. L'architecture Flutter que tout le monde reimplemente, prete en 5 minutes.

**Cible :** Developpeurs Flutter (juniors cherchant une solution cle-en-main, seniors cherchant du temps gagne sans compromis qualite).

**Probleme :** A chaque projet Flutter, les developpeurs reconstruisent la meme architecture API : gestion du refresh token, retry avec backoff, cache, erreurs. Les solutions existantes sont soit incompletes (Dio seul), soit complexes (Retrofit), soit mono-fonctionnelles (dio_cache_interceptor).

### What Makes This Special

1. **Puzzle complet assemble** — Auth + Retry + Cache + Erreurs dans un package coherent
2. **Refresh token queue** — Gestion automatique des race conditions (unique sur le marche)
3. **Config simple + overridable** — Fonctionne out-of-the-box, tout personnalisable
4. **Exceptions + Result optionnel** — Idiomatique par defaut, `.getResult()` pour pattern fonctionnel
5. **Error tracking built-in** — ErrorTrackingInterceptor pret a l'emploi (Sentry, Crashlytics, etc.)
6. **Deux modes** — API simple pour demarrer, codegen optionnel pour type-safety

**Moment aha! :** "Je n'ai plus a gerer plusieurs composants — tout est integre."

## Project Classification

| Aspect | Valeur |
|--------|--------|
| **Type** | Infrastructure Package |
| **Domaine** | Developer Infrastructure |
| **Complexite** | Medium-High |
| **Contexte** | Greenfield (package) / Brownfield (integration) |

## Success Criteria

### User Success

| Critere | Mesure | Cible |
|---------|--------|-------|
| **Temps d'integration** | Du `pub add` a la premiere requete | < 30 min |
| **Zero friction auth** | Bugs refresh token reportes | 0 issues auth/mois |
| **Adoption repeat** | Devs qui reutilisent sur projet suivant | > 80% |
| **Satisfaction** | Likes pub.dev | Ratio likes/downloads > 5% |

### Business Success

| Critere | Cible | Timeline |
|---------|-------|----------|
| **Pub points** | 160/160 | v1.0 |
| **Downloads** | 1000+ | 6 mois post-v1.0 |
| **Stars GitHub** | 100+ | 12 mois |
| **Contributeurs externes** | 3+ | 12 mois |

### Technical Success

| Critere | Cible |
|---------|-------|
| **Test coverage** | > 90% |
| **Overhead performance** | < 5ms par requete |
| **Zero breaking changes** | Entre versions minor |
| **Documentation** | 100% API publique documentee |
| **Compatibilite** | Flutter 3.x, Dart 3.x |

### Measurable Outcomes

- **v0.2 MVP** : Package fonctionnel utilise dans 1 projet reel (le tien)
- **v1.0 Stable** : 0 bugs critiques pendant 30 jours
- **Adoption** : 10 issues/PRs de la communaute = validation marche

## Product Scope

### MVP - Minimum Viable Product (v0.1 + v0.2)

- ApiClient avec config simple
- TokenProvider + AuthInterceptor avec refresh queue
- RetryInterceptor avec backoff
- LoggerInterceptor
- Hierarchie d'erreurs granulaire
- CacheStorage + annotations @Cacheable

**Timeline MVP :** 2-3 mois

### Growth Features (Post-MVP)

- apix_generator (codegen v0.3)
- Stabilisation et polish (v1.0)

### Vision (Future v1.x+)

- Offline sync
- Mock server
- apix_live (WebSocket/SSE)

## User Journeys

### Journey 1: Alex (Junior) - Premiere integration

**Opening Scene:** Alex travaille sur son premier projet Flutter pro. Le backend renvoie un 401, le token a expire. Il cherche "flutter refresh token" sur Google et tombe sur des solutions complexes avec des Completers et des Queues.

**Rising Action:** Il decouvre apix sur pub.dev. Le README montre 5 lignes de code. Il fait `pub add apix`, copie l'exemple, remplace son baseUrl et son TokenProvider.

**Climax:** Il relance l'app. Le 401 arrive, et... ca marche. Le token s'est refresh tout seul. Aucune modification de son code metier.

**Resolution:** Alex n'a plus peur des APIs. Il comprend mieux les patterns grace au code source lisible d'apix. Il le reutilisera sur son prochain projet.

---

### Journey 2: Sarah (Senior) - Migration projet existant

**Opening Scene:** Sarah maintient un projet Flutter avec du code Dio custom. Le refresh token a des race conditions. Elle n'a pas le temps de tout refactoriser.

**Rising Action:** Elle evalue apix. Elle lit le code source, verifie la qualite. Elle fait un POC : remplace son code auth par apix en gardant son TokenProvider existant.

**Climax:** Les tests passent. Le code est plus simple. Les race conditions ont disparu. Elle peut personnaliser le retry et le cache selon ses besoins.

**Resolution:** Sarah adopte apix. Elle contribue un fix sur GitHub. Elle recommande le package a son equipe.

---

### Journey 3: Marc (Lead Tech) - Standardisation equipe

**Opening Scene:** Marc revoit le code de 3 projets Flutter de son equipe. Chacun a sa propre implementation API. Maintenance cauchemardesque.

**Rising Action:** Il evalue apix comme standard d'equipe. Il cree un template de projet avec apix preconfigure. Il redige un guide interne.

**Climax:** Les nouveaux devs sont productifs en 1 jour au lieu d'une semaine. Les bugs API chutent de 80%.

**Resolution:** apix devient le standard. Marc contribue des suggestions d'amelioration via GitHub issues.

---

### Journey 4: Contributeur externe - Premiere PR

**Opening Scene:** Thomas, dev senior dans une startup, utilise apix depuis 2 mois. Il decouvre un edge case : quand le refresh token expire pendant une requete multipart, le retry echoue silencieusement.

**Rising Action:** Il ouvre une issue GitHub avec reproduction minimale. Il lit CONTRIBUTING.md, fork le repo, et decouvre une architecture claire et testable. Il ecrit un fix avec 3 tests unitaires couvrant le cas.

**Climax:** Sa PR recoit un review constructif en 48h. Apres un ajustement mineur, elle est mergee. Il est credite dans le CHANGELOG et remercie publiquement.

**Resolution:** Thomas devient contributeur regulier. Il repond aux issues, propose des ameliorations. La communaute grandit organiquement autour de contributeurs investis.

### Journey Requirements Summary

| Journey | Capabilities revelees |
|---------|----------------------|
| **Alex (Junior)** | README clair, exemple minimal, zero config par defaut |
| **Sarah (Senior)** | Code source lisible, extensibilite, migration path |
| **Marc (Lead)** | Documentation equipe, best practices, stabilite |
| **Contributeur** | CONTRIBUTING.md, tests, CI, issue templates |

## Innovation & Novel Patterns

### Detected Innovation Areas

1. **Integration Innovation** — Assemblage de composants existants (auth, retry, cache, erreurs) dans un package coherent. Aucun concurrent ne fait ca.

2. **Refresh Token Queue** — Gestion automatique des race conditions lors du refresh. Les devs reimplementent ce pattern avec bugs. apix le resout definitivement.

3. **Zero-Config DX** — `ApiClient(baseUrl: '...')` fonctionne immediatement. Pas de setup complexe, pas de boilerplate.

### Market Context & Competitive Landscape

| Concurrent | Forces | Manque |
|------------|--------|--------|
| **Dio** | Flexible, populaire | Tout a implementer |
| **Retrofit** | Codegen mature | Config verbose, pas d'auth/cache |
| **Chopper** | Leger | Pas d'auth, pas de cache |

**Gap exploite :** Infrastructure invisible batteries-included.

### Validation Approach

- **POC interne** : Utilisation dans ton propre projet
- **Beta testers** : 3-5 devs Flutter de confiance
- **Metriques** : Temps d'integration, bugs auth reportes

### Risk Mitigation

| Risque | Mitigation |
|--------|------------|
| **Adoption faible** | README killer, exemples clairs |
| **Bugs critiques** | Coverage > 90%, tests edge cases |
| **Concurrence copie** | First-mover advantage, communaute |

## Infrastructure Package Specific Requirements

### Project-Type Overview

**apix** est un package Flutter d'infrastructure destine a etre integre dans des projets existants ou nouveaux. Il doit etre stable, bien documente, et offrir une API claire et extensible.

### Technical Architecture Considerations

**Architecture en couches :**

```
ApiClient (Entry Point)
    |
Interceptor Layer (Auth, Retry, Logger, Cache)
    |
Transport Layer (Dio)
    |
Response Mapper (JSON -> Models, Errors)
```

**Principes techniques :**
- Dio comme seule dependance HTTP (pas d'abstraction multi-client)
- Interceptors configurables et extensibles
- CacheStorage abstrait (SharedPrefs par defaut, injectable)
- Erreurs typees avec hierarchie granulaire

### API Design Requirements

| Aspect | Requirement |
|--------|-------------|
| **Entry Point** | `ApiClient` unique, configurable |
| **Config** | Objets `*Config` (AuthConfig, RetryConfig, CacheConfig) |
| **Extensibilite** | Custom interceptors supportes |
| **Type Safety** | Generics pour responses, erreurs typees |

### Compatibility Requirements

| Aspect | Cible |
|--------|-------|
| **Dart SDK** | >= 3.0.0 |
| **Flutter** | >= 3.10.0 |
| **Platforms** | iOS, Android, Web, macOS, Windows, Linux |
| **Dio** | ^5.0.0 |

### Package Structure

```
apix/
  lib/
    src/
      client/        # ApiClient, config
      interceptors/  # Auth, Retry, Logger, Cache
      errors/        # Exception hierarchy
      cache/         # CacheStorage, strategies
    apix.dart        # Public exports
  example/           # Example app
  test/              # Unit + integration tests
```

### Implementation Considerations

- **Null Safety** : Full null safety
- **Tree Shaking** : Exports granulaires pour optimiser bundle size
- **Testing** : Mockable via interfaces (TokenProvider, CacheStorage)
- **Logging** : Mode dev uniquement, pas de logs en production

## Project Scoping & Phased Development

### MVP Strategy & Philosophy

**MVP Approach :** Problem-Solving MVP
- Resoudre le probleme core (API client avec auth/retry/cache)
- Fonctionnel et utilisable en production
- Valider avec 1 projet reel (le tien)

**Resource Requirements :** 1 developpeur (toi), 2-3 mois

### MVP Feature Set (Phase 1 = v0.1 + v0.2)

**Core User Journeys Supported :**
- Alex (Junior) : Integration rapide, zero config
- Sarah (Senior) : Migration, extensibilite

**Must-Have Capabilities :**
- [ ] ApiClient avec config simple
- [ ] TokenProvider + AuthInterceptor + refresh queue
- [ ] RetryInterceptor avec backoff configurable
- [ ] LoggerInterceptor (mode dev)
- [ ] Hierarchie d'erreurs granulaire
- [ ] CacheStorage abstrait + SharedPrefs default
- [ ] Annotations @Cacheable, @NoCache
- [ ] Documentation README + API docs
- [ ] Example app fonctionnelle
- [ ] Tests coverage > 90%

### Post-MVP Features

**Phase 2 (v0.3 - SecureTokenProvider) :** ✅
- SecureStorageService (wrapper flutter_secure_storage)
- SecureTokenProvider (implementation prete a l'emploi de TokenProvider)
- AuthConfig updates (refreshEndpoint, refreshHeaders, onTokenRefreshed)
- Simplified refresh flow (URL only, raw Response returned)

**Phase 3 (v1.0.0 - First Stable Release) :** ✅
- Stabilisation, bug fixes
- Documentation complete
- 401 tests passants

**Phase 4 (v1.0.1 - Unified Configuration API) :** ✅
- `authConfig` parameter in ApiClientFactory.create
- `retryConfig` parameter in ApiClientFactory.create
- `cacheConfig` parameter in ApiClientFactory.create
- `loggerConfig` parameter in ApiClientFactory.create
- `errorTrackingConfig` parameter in ApiClientFactory.create
- `metricsConfig` parameter in ApiClientFactory.create
- README reecrit avec nouvelle API unifiee

**Phase 5 (v1.4.0 - Typed Response Methods Redesign) :**
- 3-level response handling: Standard / Parse+Decode / Data
- `ApiClientConfig.dataKey` for envelope unwrapping
- 20 new Data methods (GET & POST) with OrNull/List/ListOrEmpty variants
- Removed legacy OrNull and List methods (replaced by Data family)

**Phase 6 (v1.x+ - Expansion) :**
- apix_generator (codegen Retrofit-like)
- Offline sync (mutations persistees)
- Mock server (tests integration)
- apix_live (WebSocket/SSE)

### Risk Mitigation Strategy

| Type | Risque | Mitigation |
|------|--------|------------|
| **Technique** | Race conditions refresh | Tests exhaustifs, edge cases documentes |
| **Marche** | Adoption faible | README killer, exemples clairs, dogfooding |
| **Resource** | Temps limite | MVP lean, features non-essentielles reportees |

## Functional Requirements

### Client Configuration

- FR1: Developer can create an ApiClient with minimal configuration (baseUrl only)
- FR2: Developer can customize timeout settings per ApiClient instance
- FR3: Developer can provide custom interceptors to extend functionality
- FR4: Developer can change configuration at runtime

### Authentication

- FR5: Developer can provide a TokenProvider for authentication
- FR6: System can automatically attach auth tokens to requests
- FR7: System can detect 401 responses and trigger token refresh
- FR8: System can queue concurrent requests during token refresh
- FR9: System can retry queued requests after successful refresh
- FR10: Developer can customize refresh behavior via AuthConfig

### Retry Logic

- FR11: System can automatically retry failed requests
- FR12: Developer can configure retry attempts and delays
- FR13: Developer can specify which HTTP status codes trigger retry
- FR14: System can apply exponential backoff between retries
- FR15: Developer can disable retry for specific requests

### Caching

- FR16: Developer can mark endpoints as cacheable via annotations
- FR17: System can store responses in cache storage
- FR18: Developer can choose cache strategy (CacheFirst, NetworkFirst, HttpCacheAware)
- FR19: System can deduplicate identical concurrent requests
- FR20: Developer can provide custom CacheStorage implementation
- FR21: Developer can invalidate cache programmatically

### Error Handling

- FR22: System can map HTTP errors to typed exceptions
- FR23: System can map network errors to typed exceptions
- FR24: Developer can catch specific exception types
- FR25: System can provide detailed error information (status, message, body)
- FR39: Developer can use `.getResult()` for functional Result<T,E> pattern instead of exceptions

### Request/Response

- FR26: Developer can make GET, POST, PUT, DELETE, PATCH requests
- FR27: Developer can send JSON body with requests
- FR28: Developer can send multipart/form-data requests
- FR29: System can deserialize JSON responses to Dart objects (optional, raw JSON accessible)
- FR30: Developer can access raw response when needed

### Logging & Debugging

- FR31: System can log requests and responses in dev mode
- FR32: Developer can enable/disable logging
- FR33: Developer can provide custom log handler

### Observability & Monitoring

- FR34: Developer can provide custom error reporter for external monitoring
- FR35: System can expose request context (breadcrumbs) to error reporters
- FR36: Developer can track request/response metrics (timing, status)
- FR37: System can report errors with full context (request, response, stack)
- FR38: Developer can create custom interceptors for monitoring (Sentry, Firebase, etc.)
- FR40: System provides built-in ErrorTrackingInterceptor with ErrorTrackingConfig (onError, onBreadcrumb, environment)
- FR41: Developer can enable/disable Sentry reporting per environment
- FR42: System automatically captures API errors to Sentry with request context

### Typed Response Methods (v1.4)

- FR54: Developer can format response.data directly via parse/decode methods (non-nullable, all verbs)
- FR55: Developer can configure a global dataKey in ApiClientConfig for envelope unwrapping (default: 'data')
- FR56: System can extract response.data[dataKey] from envelope responses via Data methods
- FR57: Developer can use DecodeData methods for JSON objects with fromJson tear-off support
- FR58: Developer can use ParseData methods for flexible types (primitives, custom parsing)
- FR59: Developer can use OrNull variants that return null when extracted data is null
- FR60: Developer can use List variants to deserialize lists from envelope responses
- FR61: Developer can use ListOrEmpty variants that return empty list when data is null
- FR62: Data methods are available for GET and POST verbs only

### Secure Token Storage (v0.3)

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

## Non-Functional Requirements

### Performance

- NFR1: Package overhead < 5ms par requete
- NFR2: Zero memory leaks sur usage prolonge
- NFR3: Pas de blocage du main thread (async pur)

### Reliability

- NFR4: Test coverage > 90%
- NFR5: Zero bugs critiques en production pendant 30 jours = stable
- NFR6: Gestion gracieuse de tous les edge cases reseau

### Integration

- NFR7: Compatible Dio ^5.0.0
- NFR8: Compatible Flutter >= 3.10.0, Dart >= 3.0.0
- NFR9: Fonctionne sur toutes les platforms (iOS, Android, Web, Desktop)
- NFR10: Pas de dependances natives requises

### Maintainability

- NFR11: Code conforme aux Effective Dart guidelines
- NFR12: 100% API publique documentee
- NFR13: Semantic versioning strict (pas de breaking changes en minor)
- NFR14: CHANGELOG maintenu a jour

### Testing

- NFR15: Tests d'integration avec mock server pour edge cases reseau
- NFR16: Tests de regression automatises sur CI pour chaque PR

