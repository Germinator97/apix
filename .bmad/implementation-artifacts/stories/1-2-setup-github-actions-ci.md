# Story 1.2: Setup GitHub Actions CI

Status: done

## Story

As a maintainer,
I want CI to run on every PR,
so that code quality is enforced automatically.

## Acceptance Criteria

1. **Given** a PR is opened
   **When** GitHub Actions runs
   **Then** `dart analyze --fatal-infos` passes

2. **Given** a PR is opened
   **When** GitHub Actions runs
   **Then** `dart format --set-exit-if-changed .` passes

3. **Given** a PR is opened
   **When** GitHub Actions runs
   **Then** `flutter test --coverage` runs

4. **Given** a PR is opened
   **When** GitHub Actions runs
   **Then** coverage report is generated

## Tasks / Subtasks

- [x] Task 1: Create GitHub Actions workflow file (AC: #1-4)
  - [x] Create `.github/workflows/ci.yaml`
  - [x] Configure trigger on push and pull_request
  - [x] Setup Flutter environment
  
- [x] Task 2: Add analyze step (AC: #1)
  - [x] Run `dart analyze --fatal-infos`
  - [x] Fail on any issues
  
- [x] Task 3: Add format check step (AC: #2)
  - [x] Run `dart format --set-exit-if-changed .`
  - [x] Fail if formatting issues found
  
- [x] Task 4: Add test step with coverage (AC: #3, #4)
  - [x] Run `flutter test --coverage`
  - [x] Generate coverage report

## Dev Notes

### Architecture Requirements

**From architecture.md:**
- GitHub Actions CI: analyze, format, test, pana
- Target: Every PR must pass before merge

### Workflow Structure

```yaml
name: CI
on: [push, pull_request]
jobs:
  analyze:
    - dart analyze --fatal-infos
  format:
    - dart format --set-exit-if-changed .
  test:
    - flutter test --coverage
```

### References

- [Source: architecture.md#Starter Template Evaluation]
- [Source: epics.md#Story 1.2]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Created `.github/workflows/ci.yaml` with 3 parallel jobs
- Jobs: analyze, format, test (all independent)
- Uses Flutter 3.19.0 stable with caching
- Coverage uploaded to Codecov

### File List

- `.github/workflows/ci.yaml` - GitHub Actions CI workflow

### Change Log

- 2026-03-16: Story 1.2 implemented - GitHub Actions CI setup
