---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: ['brainstorming-session-2026-03-15-2311.md']
date: 2026-03-16
author: Germinator
status: complete
---

# Product Brief: apix

## Executive Summary

**apix** est un package Flutter qui simplifie radicalement la consommation d'APIs REST. Il combine authentification avec refresh token, retry intelligent, cache flexible et gestion d'erreurs typées dans une solution clé-en-main qui fonctionne out-of-the-box tout en restant entièrement personnalisable.

---

## Core Vision

### Problem Statement

Les développeurs Flutter passent un temps considérable à réimplémenter les mêmes patterns de communication API à chaque projet : gestion du refresh token, retry avec backoff, cache, gestion d'erreurs. Les solutions existantes sont soit incomplètes (Dio seul), soit complexes à configurer (Retrofit), soit limitées à un seul aspect (dio_cache_interceptor).

### Problem Impact

- **Temps perdu** : Réimplémentation des mêmes patterns projet après projet
- **Bugs récurrents** : Race conditions refresh token, edge cases réseau mal gérés
- **Inconsistance** : Chaque projet a sa propre implémentation, maintenance difficile
- **Courbe d'apprentissage** : Les juniors doivent maîtriser des concepts complexes

### Why Existing Solutions Fall Short

- **Dio** : Puissant mais brut — tout est à construire
- **Retrofit/Chopper** : Focalisés sur le codegen, pas sur les comportements runtime
- **Packages cache** : Mono-fonctionnels, ne s'intègrent pas avec auth/retry

Aucune solution n'offre : refresh token avec queue + retry intelligent + cache + erreurs typées dans un package cohérent.

### Proposed Solution

**apix** — Un client API Flutter batteries-included :
- `ApiClient(baseUrl: '...')` fonctionne immédiatement
- Auth avec TokenProvider et refresh queue automatique
- Retry intelligent avec backoff et codes configurables
- Cache opt-in par annotations (@Cacheable) avec strategies (CacheFirst, NetworkFirst, HttpCacheAware)
- Hiérarchie d'erreurs granulaire et typée + `.getResult()` optionnel pour pattern fonctionnel
- Observabilité : SentryInterceptor built-in + custom interceptors pour autres (Firebase, etc.)
- Deux modes : simple (API directe) et codegen (annotations Retrofit-like)

### Key Differentiators

1. **Refresh token queue** — Gestion automatique des race conditions (unique)
2. **Offline sync** — Mutations persistées et sync au retour online (unique)
3. **Config simple + overridable** — Defaults sensés, tout personnalisable
4. **Observabilité extensible** — Custom interceptors pour Sentry, Firebase Crashlytics, etc.
5. **Deux packages complémentaires** — apix (core) + apix_generator (codegen optionnel)

---

## Target Users

### Primary Users

#### Dev Flutter Junior (Alex)

**Profil :** 1-2 ans d'expérience Flutter, maîtrise les bases mais n'a pas encore implémenté de patterns avancés (refresh token, retry, cache).

**Frustrations actuelles :**
- Passe des heures à comprendre comment gérer le refresh token proprement
- Copie-colle du code StackOverflow sans vraiment comprendre
- Bugs récurrents sur les edge cases réseau

**Ce qu'il cherche :**
- Solution qui fonctionne out-of-the-box
- Apprendre les bonnes pratiques en utilisant le package
- Gagner du temps pour se concentrer sur les features métier

**Moment "aha!" :** "J'ai juste ajouté mon TokenProvider et tout marche — même le refresh automatique !"

---

#### Dev Flutter Senior (Sarah)

**Profil :** 4+ ans d'expérience, a déjà implémenté ces patterns plusieurs fois, sait exactement ce qu'elle veut.

**Frustrations actuelles :**
- Réimplémente les mêmes patterns à chaque projet
- Maintient du code custom qui pourrait être standardisé
- Temps perdu sur du code "infrastructure" au lieu de la valeur métier

**Ce qu'elle cherche :**
- Gagner du temps sans sacrifier la qualité
- Code maintenable et bien architecturé
- Flexibilité pour customiser quand nécessaire

**Moment "aha!" :** "Le code est exactement comme je l'aurais écrit, mais en 10 minutes au lieu de 2 jours."

---

### Secondary Users

#### Lead Tech / Architecte (Marc)

**Profil :** Choisit les outils et standards pour l'équipe.

**Ce qu'il cherche :**
- Standardisation des pratiques API dans l'équipe
- Réduction de la dette technique
- Onboarding plus rapide des nouveaux devs

---

#### Freelance / Solo Dev (Léa)

**Profil :** Travaille seule sur plusieurs projets en parallèle.

**Ce qu'elle cherche :**
- Aller vite sans compromettre la qualité
- Solution réutilisable entre projets
- Moins de maintenance long-terme

---

### User Journey

1. **Découverte** : pub.dev, article Medium, recommandation d'un collègue
2. **Évaluation** : README clair, exemple minimal qui fonctionne en 5 min
3. **Adoption** : `ApiClient(baseUrl: '...')` → première requête réussie
4. **Aha! moment** : Refresh token automatique, retry transparent, erreurs typées
5. **Long-terme** : Le package devient le standard sur tous les projets

---

## Success Metrics

### User Success Metrics

| Métrique | Objectif | Mesure |
|----------|----------|--------|
| **Temps d'intégration** | < 30 minutes | Du `pub add` à la première requête réussie |
| **Satisfaction** | Likes pub.dev | Ratio likes/downloads |
| **Réduction bugs réseau** | Moins de tickets auth/retry | Issues GitHub catégorisées |

### Business Objectives

**Court terme (3 mois) :**
- v1.0 stable publiée sur pub.dev
- Documentation complète avec exemples
- 160/160 pub points

**Moyen terme (6-12 mois) :**
- Adoption croissante (likes, downloads)
- Premiers retours communauté (issues, PRs)
- Utilisation dans tes propres projets en production

**Long terme (12+ mois) :**
- Contributeurs externes actifs
- Adoption par des projets connus de la communauté Flutter
- Reconnaissance comme solution de référence pour les APIs Flutter

### Key Performance Indicators

| KPI | Cible | Timeframe |
|-----|-------|-----------|
| **Pub points** | 160/160 | v1.0 |
| **Likes pub.dev** | À définir après lancement | 6 mois |
| **Popularité pub.dev** | Top packages Flutter | 12 mois |
| **Contributeurs GitHub** | 3+ contributeurs externes | 12 mois |
| **Issues communauté** | Ratio issues/PRs sain | Continu |

---

## MVP Scope

### Core Features (v0.1 - v0.2)

**v0.1 - Fondations :**
- `ApiClient` avec config simple (baseUrl, timeout, defaults)
- `TokenProvider` abstraction pour l'auth
- `AuthInterceptor` avec refresh token queue
- `RetryInterceptor` avec backoff et codes configurables
- `LoggerInterceptor` (mode dev)
- Hierarchie d'erreurs granulaire

**v0.2 - Cache (MVP complet) :**
- `CacheStorage` abstraction + SharedPrefs default
- Annotations `@Cacheable`, `@NoCache`
- Strategies CacheFirst, NetworkFirst
- Deduplication des requetes

**MVP = v0.2** - A ce stade, le package est **pleinement fonctionnel** pour un usage en production.

---

### Out of Scope for MVP

| Feature | Version | Raison |
|---------|---------|--------|
| **apix_generator** | v0.3 | Apport supplementaire, pas essentiel |
| **Offline sync** | v1.x | Complexite additionnelle |
| **Mock server** | v1.x | Tooling, pas core |
| **apix_live (WebSocket)** | Future | Extension separee |

---

### MVP Success Criteria

| Critere | Validation |
|---------|------------|
| **Fonctionnel** | Toutes les features v0.1+v0.2 testees |
| **Documente** | README + API docs + 1 exemple complet |
| **Teste** | Coverage plus de 80 pourcent, tests unitaires + integration |
| **Publiable** | 160/160 pub points |
| **Utilisable** | Integre dans un projet reel |

---

### Future Vision

**Post-MVP :**
- v0.3 : apix_generator (codegen Retrofit-like)
- v1.0 : Stable, battle-tested
- v1.x : Offline sync, Mock server
- Future : apix_live (WebSocket/SSE)

**Long terme :**
- Solution de reference pour les APIs Flutter
- Ecosysteme de packages complementaires
- Communaute active de contributeurs

