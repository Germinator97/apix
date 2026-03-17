---
description: Start or finish an epic branch - usage: /git-epic start [epic-num] or /git-epic finish [epic-num]
---

## Git Epic Flow

### Start epic branch

```bash
git checkout develop
git pull origin develop
git checkout -b epic/{epic-num}-{epic-name}
git push origin epic/{epic-num}-{epic-name}
```

**Epic names:**
- `epic/1-foundation`
- `epic/2-error-hierarchy`
- `epic/3-core-client`
- `epic/4-authentication`
- `epic/5-retry-logic`
- `epic/6-caching`
- `epic/7-observability`
- `epic/8-documentation`

### Finish epic branch

1. Mark epic as done:
   - Update sprint-status.yaml: set epic-{epic-num} to `done`

2. Merge and push:
```bash
git checkout develop
git merge epic/{epic-num}-{epic-name} --no-ff -m "feat: Epic {epic-num} - {description}"
git push origin develop
```

### Release to master

```bash
git checkout master
git merge develop --no-ff -m "release: v{version}"
git tag v{version}
git push origin master --tags
```

### Commit convention

- `feat:` nouvelle fonctionnalité
- `fix:` bug fix
- `test:` ajout de tests
- `docs:` documentation
- `chore:` maintenance
