# apix — règles projet

Complète `~/.claude/CLAUDE.md`.

## CHANGELOG : court et condensé

**Une ligne par changement.** Ce qui a changé, et ce que le consommateur doit
faire s'il doit faire quelque chose. Rien d'autre.

Le *pourquoi*, le mécanisme, l'histoire de la découverte, la façon dont le
défaut a survécu aux revues précédentes : tout cela va dans le **message de
commit**, qui est fait pour ça et que personne ne lit en cherchant s'il doit
migrer.

Un consommateur ouvre un CHANGELOG pour répondre à une seule question : « est-ce
que ça me casse quelque chose ? ». Un pavé de trois paragraphes par entrée
enterre la réponse.

```
❌  * **Le cache est cloisonné par appelant.** `CacheConfig` gagne `varyHeaders`,
      défaut `['Authorization']`, et un condensé de ces en-têtes entre dans la
      clé. Jusqu'ici la clé décrivait seulement *ce qui* était demandé — méthode,
      URL, query — et jamais *qui* demandait. Deux comptes sur un appareil
      partageaient donc chaque entrée : se déconnecter, se reconnecter comme
      quelqu'un d'autre, et `GET /me` renvoyait le corps du compte précédent.
      [...huit lignes de plus...]

✅  * Les entrées de cache sont cloisonnées par appelant —
      `CacheConfig.varyHeaders`, défaut `['Authorization']`. Deux comptes sur un
      appareil partageaient chaque entrée. Un refresh de jeton invalide
      désormais le cache : cloisonner sur un en-tête d'identité stable pour
      l'éviter, ou `const []` pour s'en passer.
```

Sections dans cet ordre, et seulement celles qui ont du contenu :
`### Breaking`, `### Added`, `### Fixed`, `### Docs`. Regrouper les correctifs
par domaine (**Cache**, **Multipart**, **Observability**, **Client**) dès qu'il
y en a plus de cinq.

Ne jamais réécrire une section déjà publiée sur pub.dev : ce texte est en ligne.

## Version

Numérotée **au moment de publier**, pas au moment de corriger. Trois endroits
doivent bouger ensemble — `pubspec.yaml`, l'extrait d'installation du README, et
le titre de section du CHANGELOG. `test/readme_claims_test.dart` tombe si on n'en
change que deux.

## Les 5 surfaces d'une modification

Toute modification du paquet en touche cinq : `README.md`, `CHANGELOG.md`,
`doc/api` (régénérer avec `dart doc .`), et les **deux** exemples —
`example/example.dart` et le dépôt voisin `apix_example_app`.

`doc/api` embarque le numéro de version dans chaque page : un bump de version
seul demande déjà une régénération complète.
