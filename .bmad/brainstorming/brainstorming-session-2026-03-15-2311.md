---
stepsCompleted: [1, 2, 3, 4]
inputDocuments: []
session_topic: 'Package Flutter API Client - Architecture et fonctionnalités'
session_goals: 'Explorer fonctionnalités additionnelles, Challenger architecture, Identifier edge cases, Valider/améliorer design'
selected_approach: 'ai-recommended'
techniques_used: ['Assumption Reversal', 'Reverse Brainstorming', 'SCAMPER Method', 'Six Thinking Hats']
ideas_generated: 60
session_status: 'completed'
session_date: '2026-03-16'
---

# Session de Brainstorming — Flutter API Client Package

**Date:** 2026-03-15
**Participant:** Germinator

---

## Session Overview

**Topic:** Package Flutter API Client avec architecture en couches (Interceptors, Transport, Response Mapper, Cache Manager, Observability)

**Goals:**
- Explorer des fonctionnalités additionnelles
- Challenger les choix architecturaux
- Identifier les edge cases potentiels
- Trouver des solutions à des problèmes spécifiques
- Valider et améliorer le design actuel

---

## Architecture de référence

```
App / Widgets
     │
     ▼
FlutterApiClient (Entry Point)
     │
     ▼
Interceptor Layer
├── AuthInterceptor      → gère refresh token
├── RetryInterceptor     → retry intelligent & backoff
├── LoggerInterceptor    → console/log
├── ErrorTrackingInterceptor → remontée erreurs / monitoring
├── MultipartInterceptor → upload fichiers
└── ... autres plugins
     │
     ▼
Transport Layer (DioTransport / HttpTransport)
     │
     ▼
Response Mapper (Type-safe, JSON → Models, Error Mapping)
     │
     ▼
Cache Manager (CacheFirst, NetworkFirst, Deduplication)
     │
     ▼
Observability (Logs, Sentry, Metrics)
     │
     ▼
Result / Model
```

**Principes clés:**
- Pipeline extensible via interceptors
- Cache et déduplication transparents
- Client type-safe avec exceptions claires
- Observabilité et monitoring intégrés par défaut

---

## Technique Selection

**Approche:** Recommandations IA personnalisées
**Contexte:** Architecture technique multi-couches + exploration + validation

**Techniques sélectionnées:**
1. **Assumption Reversal** — Challenger les hypothèses implicites
2. **Reverse Brainstorming** — Identifier les edge cases via les scénarios de failure
3. **SCAMPER Method** — Explorer systématiquement les variations
4. **Six Thinking Hats** — Validation croisée multi-perspective

---

## Ideas & Exploration

### Technique 1: Assumption Reversal

**Interceptors:**
- [Archi #1] Ordre = convention package (pas de gestion manuelle par le dev)
- [Archi #2] Conditions internes aux interceptors (pas de booléens externes)
- [Config #2] Codes HTTP configurables avec defaults (retryOnCodes, refreshOnCodes)

**Auth/Refresh:**
- [Auth #1] Flow refresh avec queue: check HTTP → check refresh failure → queue si refresh en cours → replay → catch final
- [Auth #2] onSessionExpired event pour refresh token expiré
- [Auth #3] TokenProvider abstraction {getToken, saveToken, clearToken}
- [Retry #1] maxAttempts = refresh + retry combinés
- [Retry #2] Intégration avec Deduplicate
- [Retry #3] resetTimeoutAfterRefresh configurable (default: false)

**Transport:**
- [Transport #1] Dio uniquement, timeout configurable, single instance

**Cache:**
- [Cache #1] Cache JSON brut, parse à chaque retour
- [Cache #2] Annotations par requête (@Cacheable, @NoCache), pas de cache par défaut

**Mapper:**
- [Mapper #1] Parsing synchrone

**Observability:**
- [Obs #1] Pas d'abstractions — interceptors custom du dev
- [Obs #2] Logs = mode dev uniquement
- [Obs #3] Pas de metrics (responsabilité backend)

**Entry Point:**
- [Multi #1] Support multi-instance réel
- [API #1] Config modifiable à runtime (baseUrl, tokenProvider)
- [API #2] Deux niveaux d'API (bas niveau + helpers haut niveau)

### Technique 2: Reverse Brainstorming

**Réseau hostile:**
- [Fail #1] Upload interrompu → Progress callback, dev gère resume
- [Fail #2] Réponse post-timeout → CancelToken annule vraiment
- [Fail #3] JSON tronqué → ApiParsingException avec contexte

**Auth/Token:**
- [Fail #4] Refresh race → Lock + queue (déjà couvert)
- [Fail #5] Offline token expire → NetworkException ≠ SessionExpired
- [Fail #6] TokenProvider throws → TokenProviderException spécifique

**Cache:**
- [Fail #7] Cache full → Silencieux + callback optionnel
- [Fail #8] Cache corrompu → Auto-heal + fallback network

**API/Backend:**
- [Fail #9] 200 avec erreur body → responseValidator callback
- [Fail #10] SSL invalide → allowBadCertificates + pinning
- [Fail #11] Rate limiting 429 → Respect Retry-After header
- [Fail #12] Redirect infini → maxRedirects config
- [Fail #13] Content-Type wrong → UnexpectedContentTypeException
- [Fail #14] Body vide sur 200 → Future<void> vs Future<T>

**Lifecycle/Concurrence:**
- [Fail #15] App killed mid-POST → Idempotency keys (doc)
- [Fail #16] Multiple isolates → TokenProvider thread-safe (doc)
- [Fail #17] Hot restart → Non-issue

**Device/Platform:**
- [Fail #18] WiFi → 4G mid-request → RetryInterceptor couvre
- [Fail #19] Mode avion refresh → Déjà couvert
- [Fail #20] Background iOS → backgroundMode config avec timeouts courts

### Technique 3: SCAMPER

**Substitute:**
- [S #1] CacheStorage abstraction + SharedPrefs default
- [S #2] Exceptions default + `.getResult()` optionnel pour pattern fonctionnel
- [S #3] HttpCacheAware strategy : respecte les headers HTTP cache quand disponibles, sinon utilise notre cache custom

**Combine:**
- [C #1] Auth+Retry coordonnés mais séparés
- [C #2] Logger + Sentry = Observability unifiée (interceptor custom dev)

**Adapt:**
- [A #1] S'inspirer de Retrofit (annotations)
- [A #2] S'inspirer de TanStack Query (stale-while-revalidate)

**Modify:**
- [M #1] TypeSafe: deux packages (apix + apix_generator)
- [M #2] Config: conventions sensées par défaut
- [M #3] Erreurs: hiérarchie granulaire
- [M #4] Logs: structured logging optionnel

**Put to other uses:**
- [P #1] Mock server pour tests d'intégration
- [P #3] Offline sync (mutations persistées, sync quand online)

**Eliminate:**
- [E #1] Notre propre cache (pas dio_cache_interceptor)
- [E #2] Interceptors built-in gardés avec *Config modifiables (RetryConfig, AuthConfig, CacheConfig, ErrorTrackingConfig, etc.)

**Reverse:**
- [R #1] Response-driven avec overrides + code généré modifiable (approche hybride: base générée + extension manuelle)
- [R #2] Mock server généré depuis le client
- [R #3] WebSocket/SSE → extension future apix_live
- [R #5] Config file en option secondaire (code first)

### Technique 4: Six Thinking Hats

**🎩 White Hat (Faits):**
- Design complet couvrant: Transport, Auth, Retry, Cache, Erreurs, Config
- Deux packages: apix (core) + apix_generator (optionnel)
- Extras: Mock server, Offline sync

**🎩 Red Hat (Émotions):**
- Confiant que le design couvre les besoins réels

**🎩 Yellow Hat (Avantages):**
- DX simple (out-of-the-box)
- Extensible (interceptors, storage, provider)
- Pragmatique (pas de sur-engineering)
- Flexible (deux modes: simple + codegen)

**🎩 Black Hat (Risques):**
- Différenciation claire vs concurrence (Retrofit, Chopper, Dio seul)
- Features uniques: Refresh queue, Offline sync, Mock server, Config simple

**🎩 Green Hat (Alternatives):**
- CLI tool (`apix init`)
- VS Code extension (snippets)
- Playground web

**🎩 Blue Hat (Processus):**
- Roadmap: v0.1 (Core) → v0.2 (Cache) → v0.3 (Generator) → v1.0 (Stable)
- Releases selon readiness, pas calendrier fixe
- Qualité > Cadence

---

## Résumé final

### Architecture validée

```
┌─────────────────────────────────────────────────────────┐
│                      ApiClient                          │
│  (baseUrl, tokenProvider, *Config avec defaults)        │
└─────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────┐
│                  Interceptor Layer                      │
│  (ordre = convention package)                           │
├─────────────────────────────────────────────────────────┤
│  1. Logger (pré)     → logs dev only                    │
│  2. Multipart        → transform body                   │
│  3. Auth             → TokenProvider, refresh queue     │
│  4. [réseau]                                            │
│  5. Retry            → maxAttempts, codes, backoff      │
│  6. Cache            → JSON brut, annotations opt-in    │
│  7. Logger (post)    → logs dev only                    │
└─────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────┐
│                   Transport Layer                       │
│  (Dio uniquement, timeout configurable)                 │
└─────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────┐
│                   Response Mapper                       │
│  (synchrone, exceptions granulaires + Result optionnel) │
└─────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────┐
│                       Result                            │
│  (Model typé ou Exception claire)                       │
└─────────────────────────────────────────────────────────┘
```

### Packages

| Package | Contenu |
|---------|---------|
| **apix** | Core, Interceptors, Cache, Erreurs |
| **apix_generator** | Annotations, Codegen (hybride: base + extension) |
| **apix_live** | WebSocket/SSE (future) |

### Roadmap

| Version | Contenu |
|---------|---------|
| v0.1 | ApiClient, Auth, Retry, Logger, Erreurs |
| v0.2 | Cache, CacheStorage, Annotations |
| v0.3 | apix_generator (codegen) |
| v1.0 | Stable, documenté, testé |
| v1.x | Offline sync, Mock server |

### Statistiques session

- **Techniques utilisées:** 4 (Assumption Reversal, Reverse Brainstorming, SCAMPER, Six Thinking Hats)
- **Idées générées:** ~60+
- **Durée:** ~2h

