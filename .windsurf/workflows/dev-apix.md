---
description: Create and implement apix story - usage: /dev-apix [story-key] or /dev-apix next
---

## Dev Apix Story

**Usage:**
- `/dev-apix 1-1-initialize-package-structure` — Develop specific story
- `/dev-apix next` — Develop next backlog story

### Step 1: Determine story

If story-key provided (e.g., `1-1-initialize-package-structure`):
- Check if story file exists: `.bmad/implementation-artifacts/stories/{story-key}.md`
- If NOT exists → Create it first with `bmad-create-story` for story {story-key}
- If exists → Proceed to implementation

If `next` provided:
- Read `.bmad/implementation-artifacts/sprint-status.yaml`
- Find first story with status `backlog` or `ready-for-dev`
- Create story file if needed with `bmad-create-story`

### Step 2: Implement story

// turbo
Invoke `bmad-dev-story` with the story file path:
`.bmad/implementation-artifacts/stories/{story-key}.md`

### Step 3: After completion

Suggest running `bmad-code-review` with a different LLM for best results.

---

**Context files to load:**
- `.bmad/planning-artifacts/architecture.md` — ADRs and patterns
- `.bmad/planning-artifacts/epics.md` — Story details and ACs
- `.bmad/implementation-artifacts/sprint-status.yaml` — Current status
