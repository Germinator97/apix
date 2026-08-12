---
stepsCompleted: ['step-01-motivation', 'step-02-architecture', 'step-03-decoupage', 'step-04-migration', 'step-05-release-plan']
status: draft
inputDocuments: ['epics.md', 'architecture.md', 'brainstorming-session-2026-03-15-2311.md']
workflowType: 'modularization'
project_name: 'apix'
target_version: '3.0.0'
user_name: 'Germinator'
date: '2026-05-04'
---

# ApiX 3.0 — Plan de Modularisation

> Référence pour l'éclatement du package monolithique `apix` 2.x en monorepo multi-packages versionnés indépendamment.

---

## 1. Motivation

### 1.1 Problèmes du package monolithique 2.x

- **Dépendances obligatoires non utilisées** : `flutter_secure_storage` (≈ 800 KB Android, 400 KB iOS) et `sentry_flutter` (≈ 1.2 MB) sont chargés même si l'app utilise un `TokenProvider` custom et un autre service de monitoring (Crashlytics, DataDog, …).
- **Couplage Flutter** : `apix` actuel dépend du SDK Flutter via `flutter_secure_storage`. Impossible d'utiliser le core dans un binaire Dart pur (CLI, microservice, dart_frog).
- **Versionning trop large** : un fix mineur sur `SentrySetup` force un bump `apix` global, tous les consommateurs en sont notifiés alors que la majorité ne l'utilisent pas.
- **Extensions futures bloquées** : `apix_offline`, `apix_generator`, `apix_live` (WebSocket/SSE) — listés dès le brainstorming initial — ne peuvent pas vivre dans le même package sans alourdir `apix` pour tout le monde.

### 1.2 Bénéfices attendus

- **Footprint** : une CLI Dart consomme `apix_core` seul → ~150 KB de dependencies au lieu de ~3 MB.
- **Évolution indépendante** : `apix_sentry` peut suivre les breaking changes de `sentry_flutter` (9.x → 10.x) sans toucher à `apix_core`.
- **Lisibilité du domaine** : chaque package a une responsabilité unique et testable isolément.
- **Onboarding** : un développeur lit `apix_core` (~1500 lignes) au lieu d'un package opaque de 4000+ lignes.

### 1.3 Non-objectifs

- Pas de réécriture du core. Le code existant est mature, testé (couverture > 90 %), et stable depuis 2.0.0.
- Pas de changement d'API publique côté `apix` (l'utilisateur final continue à `import 'package:apix/apix.dart'`).
- Pas de support multi-transport : Dio reste le seul transport (NFR7 inchangé).

---

## 2. Architecture cible

### 2.1 Diagramme de dépendances

```
                              ┌──────────────┐
                              │     apix     │  meta-package (re-export)
                              │  (umbrella)  │
                              └──────┬───────┘
                                     │ exporte tout
                  ┌──────────────────┼───────────────────┐
                  │                  │                   │
            ┌─────▼──────┐    ┌──────▼─────────┐  ┌──────▼────────┐
            │ apix_core  │    │ apix_secure_   │  │  apix_sentry  │
            │  (Dart)    │    │   storage      │  │   (Flutter)   │
            │            │    │   (Flutter)    │  │               │
            └─────▲──────┘    └──────┬─────────┘  └──────┬────────┘
                  │                  │                   │
                  │ dépend de        │ dépend de         │ dépend de
                  │                  ▼                   ▼
                  │          ┌──────────────────────────────┐
                  │          │  apix_core (TokenProvider,   │
                  │          │  ErrorTrackingConfig)         │
                  │          └──────────────────────────────┘
                  │
       ┌──────────┼──────────────┬──────────────┐
       │          │              │              │
 ┌─────▼────┐ ┌───▼──────┐ ┌─────▼───────┐ ┌────▼────┐
 │ apix_    │ │ apix_    │ │ apix_       │ │ apix_   │
 │ mock     │ │ offline  │ │ generator   │ │ live    │
 │ (3.1)    │ │ (3.3)    │ │ (3.2)       │ │ (4.0+)  │
 └──────────┘ └──────────┘ └─────────────┘ └─────────┘
```

### 2.2 Inventaire des packages

| Package | Type | Version cible | Responsabilité | Deps externes |
|---------|------|---------------|----------------|---------------|
| `apix_core` | Dart pur | 3.0.0 | Client HTTP, interceptors, Result, exceptions, cache in-memory | `dio`, `crypto` |
| `apix_secure_storage` | Flutter | 3.0.0 | `SecureStorageService`, `SecureTokenProvider` | `apix_core`, `flutter_secure_storage` |
| `apix_sentry` | Flutter | 3.0.0 | `SentrySetup` + helpers Sentry | `apix_core`, `sentry_flutter` |
| `apix` (umbrella) | Flutter | 3.0.0 | Re-export pour rétrocompatibilité d'imports | `apix_core`, `apix_secure_storage`, `apix_sentry` |
| `apix_mock` | Dart pur | 3.1.0 | Mock server pour tests d'intégration | `apix_core`, `shelf` |
| `apix_generator` | Dart pur | 3.2.0 | Annotations + codegen Retrofit-like | `build_runner`, `source_gen`, `analyzer` |
| `apix_offline` | Flutter | 3.3.0 | Queue de mutations persistées + replay | `apix_core`, `sqflite` ou `drift` |
| `apix_live` | Flutter | 4.0.0+ | WebSocket / Server-Sent Events | `apix_core`, `web_socket_channel` |

---

## 3. Découpage détaillé

### 3.1 `apix_core` (Dart pur)

**Contenu déplacé depuis `lib/src/` actuel** :
- `client/` (api_client, api_client_config, api_client_factory, multipart_interceptor)
- `auth/auth_config.dart`, `auth/auth_interceptor.dart`, `auth/token_provider.dart`
- `cache/` (cache_config, cache_interceptor, cache_storage, cache_entry, request_deduplicator) — sans persistance disque
- `retry/` (retry_config, retry_interceptor)
- `errors/` (api_exception, http_exception, network_exception, error_mapper_interceptor)
- `logging/` (logger_config, logger_interceptor)
- `observability/error_tracking_interceptor.dart`, `observability/metrics_interceptor.dart`
- `models/result.dart`

**API publique conservée à 100 %** : aucune signature ne change.

**Migration Flutter → Dart pur** :
- Vérifier qu'aucun fichier n'importe `package:flutter/*` (rapide via `grep -r "package:flutter/" lib/src/`).
- `pubspec.yaml` : `environment: sdk: '>=3.0.0 <4.0.0'` sans `flutter:` block.
- `flutter_test` → `test` dans dev_dependencies pour les tests qui ne touchent pas à Flutter.

### 3.2 `apix_secure_storage` (Flutter)

**Contenu déplacé** :
- `auth/secure_storage_service.dart`
- `auth/secure_token_provider.dart`

**API publique** : inchangée. Importable via `package:apix_secure_storage/apix_secure_storage.dart`.

**Dépendance** : importe `TokenProvider` depuis `apix_core`.

### 3.3 `apix_sentry` (Flutter)

**Contenu déplacé** :
- `observability/sentry_setup.dart`

**Note** : `ErrorTrackingInterceptor` reste dans `apix_core` (générique, pattern callback). Seuls les helpers Sentry-specific partent.

### 3.4 `apix` (umbrella, rétrocompatibilité)

```dart
// lib/apix.dart
export 'package:apix_core/apix_core.dart';
export 'package:apix_secure_storage/apix_secure_storage.dart';
export 'package:apix_sentry/apix_sentry.dart';
```

**Pourquoi garder ce package ?** : zero-effort migration pour les apps existantes. `import 'package:apix/apix.dart'` continue de fonctionner exactement comme avant.

**Période de vie** : maintenu pendant toute la 3.x (≥ 12 mois). Dépréciation envisagée en 4.0 si l'usage de l'umbrella devient marginal (mesure via analytics pub.dev).

### 3.5 `apix_mock` (NEW — 3.1)

Mock server in-process basé sur `package:shelf`. Permet aux tests d'intégration de définir des routes et payloads sans dépendance externe.

```dart
final mock = ApixMockServer()
  ..on('GET', '/users/1', (req) => MockResponse.json({'id': 1, 'name': 'Alex'}))
  ..on('POST', '/login', (req) => MockResponse.status(401));

await mock.start();
final client = ApiClient(baseUrl: mock.baseUrl);
```

### 3.6 `apix_offline` (NEW — 3.3)

Queue de mutations (POST/PUT/PATCH/DELETE) persistées localement, rejouées au retour online. Stratégies de résolution de conflits configurables (last-write-wins, custom callback).

Reporté à 3.3 car nécessite un travail de design sur la sérialisation des requêtes (FormData, fichiers, headers dynamiques) et la gestion des conflits.

### 3.7 `apix_generator` (NEW — 3.2)

Annotations `@RestService`, `@GET`, `@POST`, etc., générant un client typé via `build_runner`. Approche hybride brainstorming `[Reverse #1]` : base générée + extension manuelle possible.

### 3.8 `apix_live` (NEW — 4.0+)

Hors scope 3.x. À évaluer après stabilisation de la 3.x et selon le besoin réel.

---

## 4. Stratégie de migration

### 4.1 Phase A — Préparation (pendant 2.x)

- [x] Audit du code (effectué : 2026-05-04, voir conversation Claude).
- [ ] Identifier les imports `package:flutter/*` dans `lib/src/` qui ne sont pas dans `auth/secure_*` ou `observability/sentry_setup.dart` — toute occurrence doit être traitée avant le split.
- [ ] Documenter publiquement l'intention 3.0 (CHANGELOG, README, issue GitHub épinglée) au moment de la release 2.2.0.

### 4.2 Phase B — Refactor monorepo (3.0-rc.1 à rc.N)

1. Initialiser **Melos** à la racine, créer `packages/apix_core/`, `packages/apix_secure_storage/`, `packages/apix_sentry/`, `packages/apix/`.
2. Déplacer les fichiers selon § 3, mettre à jour les imports relatifs (`package:apix/src/...` → `package:apix_core/src/...` à l'intérieur du nouveau package).
3. Ajuster les `pubspec.yaml` de chaque package (deps internes via `path:` en dev, version pinnée en publication).
4. Migrer la suite de tests : chaque test reste dans le package qui contient le code testé.
5. CI : un seul workflow GitHub Actions exécute `melos run analyze`, `melos run test`, `melos run format-check`.

### 4.3 Phase C — Release 3.0.0

1. Publication coordonnée de `apix_core`, `apix_secure_storage`, `apix_sentry` puis `apix` (l'umbrella en dernier car dépend des 3 autres).
2. Annonce coordonnée : CHANGELOG dans chaque package + tag `v3.0.0` sur l'umbrella.
3. Migration guide dans `apix/MIGRATION_2_TO_3.md` couvrant :
   - Cas 1 (par défaut) : aucun changement, garder `package:apix/apix.dart`.
   - Cas 2 (footprint) : remplacer par les imports granulaires `apix_core` / `apix_secure_storage` / `apix_sentry`.

### 4.4 Phase D — Maintenance 3.x

- Versions indépendantes : un patch dans `apix_sentry` ne bump pas `apix_core`.
- L'umbrella `apix` re-pin les nouvelles versions de ses sous-packages à chaque release coordonnée majeure.

---

## 5. Plan de release indicatif

| Version | Contenu | Effort estimé | Dépendance |
|---------|---------|---------------|------------|
| 2.1.0 | Fixes contrat 2.0.0 (6 items) | ~3 j | — |
| 2.2.0 | Production hardening (5 items) | ~5 j | 2.1.0 livré |
| **3.0.0-rc.1** | Split monorepo + umbrella | ~8 j | 2.2.0 livré |
| **3.0.0** | Stable monorepo | ~2 j | rc validés en interne sur les apps consommatrices |
| 3.1.0 | `apix_mock` | ~5 j | 3.0 stable |
| 3.2.0 | `apix_generator` (MVP : @GET, @POST, path params, query params, body) | ~15 j | 3.0 stable |
| 3.3.0 | `apix_offline` | ~12 j | 3.0 stable |
| 4.0.0 | `apix_live` (WebSocket/SSE) | tbd | tbd |

Les versions 3.1+ sont **opportunistes** : pas de calendrier ferme. Suivre la maxime brainstorming `[🎩 Blue Hat]` : « Releases selon readiness, pas calendrier fixe. Qualité > Cadence ».

---

## 6. Outillage

### 6.1 Monorepo : Melos

Choix : `melos` (de Invertase) — standard de facto pour les monorepos Dart/Flutter.

```yaml
# melos.yaml (racine)
name: apix_workspace
packages:
  - packages/*

scripts:
  analyze:
    run: melos exec -- "fvm dart analyze"
  test:
    run: melos exec -- "fvm flutter test"
  format-check:
    run: melos exec -- "fvm dart format --set-exit-if-changed ."
```

### 6.2 Structure de dossiers cible

```
apix/                                 (racine du repo, devient workspace)
├── melos.yaml
├── README.md                         (renvoi vers chaque package)
├── packages/
│   ├── apix_core/
│   │   ├── lib/
│   │   ├── test/
│   │   ├── pubspec.yaml
│   │   ├── CHANGELOG.md
│   │   └── README.md
│   ├── apix_secure_storage/
│   ├── apix_sentry/
│   └── apix/                         (umbrella — pubspec uniquement, pas de lib/src)
└── .bmad/
```

### 6.3 Versioning

- **Indépendant** par package — pas de `lockstep` (sauf pour la release initiale 3.0.0 où tous bump ensemble).
- L'umbrella `apix` peut être en 3.0.x pendant que `apix_core` est en 3.1.x. Documenter la **matrice de compatibilité** dans `apix/COMPATIBILITY.md`.

### 6.4 CI/CD

- Un seul workflow GitHub Actions à la racine.
- Cache Melos partagé entre packages.
- Publication automatisée via `melos publish --no-dry-run` après tag git correspondant (à valider — sinon publication manuelle séquentielle).

---

## 7. Breaking changes

### 7.1 Liste exhaustive

| Cas utilisateur | Avant 3.0 | Après 3.0 | Mitigation |
|-----------------|-----------|-----------|------------|
| Import unique `package:apix/apix.dart` | Toujours OK | Toujours OK | Aucune action — l'umbrella est garanti |
| Footprint minimal recherché | Impossible | `apix_core` seul | Migration guide |
| App qui utilise uniquement `SentrySetup` | `package:apix/apix.dart` | `package:apix_sentry/apix_sentry.dart` (option) | Optionnel — l'import umbrella reste valide |
| Test qui mock `SecureStorageService` | `package:apix/apix.dart` | `package:apix_secure_storage/apix_secure_storage.dart` (option) | Optionnel — l'import umbrella reste valide |

### 7.2 Pourquoi 3.0 et pas 2.3 ?

- Une release qui réorganise la structure de packages **modifie la liste des dépendances effectives** de l'app cliente (ajout de 3 packages dans `pubspec.lock`).
- Même si l'API publique est identique, la convention SemVer recommande un bump majeur dès que la **structure du package change de manière observable** (nombre de packages, surface d'imports possibles).
- Permet de communiquer clairement la transition.

---

## 8. Risques & mitigation

| Risque | Probabilité | Impact | Mitigation |
|--------|-------------|--------|------------|
| Confusion utilisateurs sur quel package importer | Moyenne | Moyen | Migration guide clair, README de chaque package, FAQ |
| Régression silencieuse pendant le split | Moyenne | Élevé | Suite de tests existante (> 90 % cov) doit passer à 100 % avant 3.0.0. Tests d'intégration spécifiques sur les imports croisés |
| Désynchronisation des versions inter-packages | Faible | Moyen | Melos lockstep pour la 3.0.0, matrice de compat pour la suite |
| Charge mentale pour la maintenance | Moyenne | Faible | Standardiser via Melos scripts. Une seule CI |
| Dépréciation prématurée de l'umbrella | Faible | Élevé | Engagement écrit : umbrella maintenu ≥ 12 mois après 3.0 |
| Apps internes cassées | Faible | Élevé | RC validée en interne sur ces 3 apps avant publication 3.0.0 |

---

## 9. Décisions ouvertes

À trancher avant le démarrage de la phase B :

1. **Nom du package umbrella** : garder `apix` (recommandé pour rétrocompatibilité) ou `apix_full` ?
2. **`apix_core` ou `apix_dart`** : quel nom pour le core Dart-pur ? `apix_core` est plus parlant, `apix_dart` rappelle l'absence de Flutter.
3. **Versioning indépendant ou lockstep** : recommandation = lockstep pour 3.0.0, indépendant ensuite. À valider.
4. **`ErrorTrackingInterceptor` reste dans `apix_core`** : confirmé — le pattern callback est suffisamment générique pour rester en core. À valider lors du split.
5. **Migration des consommateurs internes** : pré-tester sur les apps internes en local avant publication. Qui s'en occupe et quand ?

---

## 10. Annexes

### 10.1 Références

- Brainstorming initial : `.bmad/brainstorming/brainstorming-session-2026-03-15-2311.md` (sections `[Reverse #3]`, `[M #1]`, `[P #1]`, `[P #3]`)
- Architecture : `.bmad/planning-artifacts/architecture.md`
- Audit 2026-05-04 : conversation Claude (résultat synthétisé en § 1.1 et § 2.2)
- Melos : https://melos.invertase.dev/

### 10.2 Glossaire

- **Umbrella package** : package qui ne contient pas de code propre, juste des `export` de packages tiers. Sert à offrir un point d'entrée unifié.
- **Lockstep versioning** : tous les packages d'un monorepo bump leur version au même rythme.
- **Phase A/B/C/D** : voir § 4.

---

_Statut : draft. Itérer avec Germinator avant passage à `ready-for-dev`._
