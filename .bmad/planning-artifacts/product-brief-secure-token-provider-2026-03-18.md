---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - brainstorming-session-2026-03-18-secure-token-provider.md
date: 2026-03-18
author: Germinator
---

# Product Brief: SecureTokenProvider

## Executive Summary

**SecureTokenProvider** est une feature d'ApiX qui fournit une implémentation prête à l'emploi de `TokenProvider` basée sur `flutter_secure_storage`. Elle simplifie drastiquement la gestion des tokens d'authentification tout en laissant au développeur le contrôle total sur le parsing et la sauvegarde.

**Proposition de valeur :** Réduire le boilerplate de ~30 lignes à 1-3 lignes tout en préservant la flexibilité du développeur.

---

## Core Vision

### Problem Statement

Les développeurs Flutter utilisant ApiX pour intégrer des APIs authentifiées doivent actuellement :
1. Implémenter manuellement l'interface `TokenProvider`
2. Configurer `FlutterSecureStorage` eux-mêmes
3. Écrire un callback `onRefresh` complet incluant l'appel HTTP et le parsing

Ce boilerplate répétitif (~30 lignes) est source d'erreurs et détourne le développeur de sa logique métier.

### Problem Impact

- **Temps perdu** : Code répétitif sur chaque projet
- **Risque d'erreurs** : Implémentation incorrecte du stockage sécurisé
- **Friction d'adoption** : Barrière à l'entrée pour les nouveaux utilisateurs d'ApiX
- **Inconsistance** : Chaque dev implémente différemment

### Why Existing Solutions Fall Short

- **Implémentation manuelle** : Chaque dev réinvente la roue
- **Packages OAuth2** : Trop complexes, couplés à des flows spécifiques
- **Pas d'intégration native** : ApiX fournit l'interface mais pas l'implémentation

### Proposed Solution

**Architecture à deux classes :**

1. **`SecureStorageService`** : Wrapper de `flutter_secure_storage`
   - `write(key, value)` / `read(key)` / `delete(key)` / `deleteAll()`
   - Point d'entrée unique pour tout stockage sécurisé
   - Réutilisable pour Firebase Auth, API keys, etc.

2. **`SecureTokenProvider`** : Implémentation de `TokenProvider`
   - Utilise `SecureStorageService` en composition
   - `saveTokens(access, refresh)` / `clearTokens()` / `getAccessToken()` / `getRefreshToken()`
   - Injecteur optionnel : `SecureTokenProvider({SecureStorageService? storage})`

3. **`refreshEndpoint`** : URL relative au `baseUrl`
   - ApiX fait l'appel HTTP automatiquement
   - Option `refreshHeaders` pour headers custom si besoin

4. **`onTokenRefreshed(Response)`** : Callback avec réponse brute
   - Même pattern que login : dev parse et sauvegarde

**Diagramme :**
```
┌─────────────────────────┐
│  SecureStorageService   │  ← Wrapper flutter_secure_storage
│  write/read/delete      │
└───────────┬─────────────┘
            │ uses
┌───────────▼─────────────┐
│  SecureTokenProvider    │  ← Implements TokenProvider
│  saveTokens/clearTokens │
└─────────────────────────┘
```

### Key Differentiators

| Aspect | Valeur |
|--------|--------|
| **Simplicité** | 1-3 lignes vs ~30 lignes de boilerplate |
| **Flexibilité** | Dev garde le contrôle sur parsing et sauvegarde |
| **Cohérence** | Même pattern login/refresh (recevoir Response, parser, sauvegarder) |
| **Extensibilité** | Storage exposé pour autres usages (secrets, préférences sécurisées) |
| **Optionnel** | `TokenProvider` reste l'interface, dev peut implémenter autrement |

---

## Target Users

### Primary Users

#### Dev Flutter Junior (Alex)

**Profil :** 1-2 ans d'expérience Flutter, maîtrise les bases mais n'a pas encore implémenté de patterns avancés (refresh token, secure storage).

**Frustrations actuelles :**
- Passe des heures à comprendre comment implémenter `TokenProvider`
- Copie-colle du code FlutterSecureStorage sans comprendre les best practices
- Bugs récurrents sur la gestion des tokens (race conditions, expiration)

**Ce qu'il cherche :**
- Solution prête à l'emploi qui fonctionne out-of-the-box
- Ne pas avoir à se soucier des détails de stockage sécurisé
- Gagner du temps pour se concentrer sur les features métier

**Moment "aha!" :** "J'ai juste créé un `SecureTokenProvider()` et tout marche !"

---

#### Dev Flutter Senior (Sarah)

**Profil :** 4+ ans d'expérience, a déjà implémenté ces patterns plusieurs fois, sait exactement ce qu'elle veut.

**Frustrations actuelles :**
- Réimplémente le même `TokenProvider` à chaque projet
- Maintient du code custom FlutterSecureStorage
- Temps perdu sur du code "infrastructure"

**Ce qu'elle cherche :**
- Gagner du temps sans sacrifier la flexibilité
- Pouvoir injecter son propre `SecureStorageService` si besoin
- Pattern cohérent login/refresh (Response brute → parse → save)

**Moment "aha!" :** "Je peux réutiliser le même `SecureStorageService` pour mes tokens ET mon Firebase Auth."

---

### Secondary Users

#### Lead Tech / Architecte (Marc)

**Profil :** Choisit les outils et standards pour l'équipe.

**Ce qu'il cherche :**
- Standardisation de la gestion des tokens dans l'équipe
- Réduction de la dette technique
- Onboarding plus rapide des nouveaux devs

---

### User Journey

1. **Découverte** : Documentation ApiX, migration depuis implémentation custom
2. **Adoption** : `SecureTokenProvider()` → `authConfig` configuré en 3 lignes
3. **Aha! moment** : Refresh automatique fonctionne, tokens persistés de façon sécurisée
4. **Long-terme** : Réutilise `SecureStorageService` pour d'autres secrets

---

## Success Metrics

### User Success Metrics

| Métrique | Objectif | Mesure |
|----------|----------|--------|
| **Temps d'intégration** | < 5 minutes | Du code existant à SecureTokenProvider fonctionnel |
| **Réduction boilerplate** | -90% | De ~30 lignes à 1-3 lignes |
| **Bugs tokens** | -80% | Moins d'issues GitHub liées aux tokens |

### Business Objectives

**Court terme :**
- Feature intégrée dans ApiX v0.x
- Documentation complète avec exemples login/refresh
- Tests unitaires coverage > 90%

**Moyen terme :**
- Adoption par les utilisateurs existants d'ApiX
- Feedback positif sur la DX
- Moins de questions sur l'implémentation TokenProvider

---

## MVP Scope

### Core Features

**SecureStorageService :**
- `write(key, value)` - Écriture sécurisée
- `read(key)` - Lecture sécurisée
- `delete(key)` - Suppression
- `deleteAll()` - Nettoyage complet

**SecureTokenProvider :**
- Implémente `TokenProvider`
- `saveTokens(access, refresh)`
- `clearTokens()`
- `getAccessToken()` / `getRefreshToken()`
- Injection optionnelle de `SecureStorageService`

**AuthConfig updates :**
- `refreshEndpoint` - URL relative au baseUrl
- `refreshHeaders` - Headers custom optionnels
- `onTokenRefreshed(Response)` - Callback réponse brute

---

### Out of Scope for MVP

| Feature | Version | Raison |
|---------|---------|--------|
| **Biométrie** | Future | Complexité additionnelle |
| **Multi-compte** | Future | Scope différent |
| **Token encryption custom** | Future | flutter_secure_storage suffit |
| **Auto-logout on expiry** | Future | Responsabilité app |

---

### MVP Success Criteria

| Critère | Validation |
|---------|------------|
| **Fonctionnel** | Login/refresh/logout testés |
| **Documenté** | README + exemples complets |
| **Testé** | Coverage > 90%, tests unitaires + integration |
| **Compatible** | Pas de breaking changes sur TokenProvider existant |

---

## Risks & Mitigations

| Risque | Impact | Mitigation |
|--------|--------|------------|
| **Dépendance flutter_secure_storage** | Moyen | Wrapper abstrait, injectable |
| **Breaking changes AuthConfig** | Élevé | Nouveaux champs optionnels uniquement |
| **Confusion TokenProvider vs SecureTokenProvider** | Moyen | Documentation claire, exemples |
| **Platform-specific issues** | Moyen | Tests sur iOS/Android/Web |

---

## Technical Considerations

### Dépendances

- `flutter_secure_storage: ^9.0.0` (optionnelle, dev l'ajoute)

### Compatibilité

- Flutter >= 3.0
- Dart >= 3.0
- iOS, Android, Web, macOS, Windows, Linux

### Architecture

```
lib/src/auth/
├── token_provider.dart          (existant - interface)
├── secure_storage_service.dart  (nouveau)
├── secure_token_provider.dart   (nouveau)
├── auth_config.dart             (modifié - nouveaux champs)
└── auth_interceptor.dart        (modifié - refresh endpoint)
