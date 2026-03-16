# Story 1.1: Initialize Package Structure

Status: review

## Story

As a developer,
I want to create the apix package with standard Flutter structure,
so that I have a solid foundation to build upon.

## Acceptance Criteria

1. **Given** the project directory exists with planning artifacts
   **When** I run `flutter create --template=package --project-name=apix .`
   **Then** the package structure is created with lib/, test/, pubspec.yaml

2. **Given** the package is created
   **When** I check analysis_options.yaml
   **Then** it is configured with recommended lints (flutter_lints)

3. **Given** the package is created
   **When** I run `flutter analyze`
   **Then** no errors or warnings are reported

4. **Given** the package is created
   **When** I run `flutter test`
   **Then** the default test passes

## Tasks / Subtasks

- [x] Task 1: Initialize Flutter package (AC: #1)
  - [x] Run `flutter create --template=package --project-name=apix .`
  - [x] Verify lib/, test/, pubspec.yaml exist
  - [x] Remove generated example files that will be replaced
  
- [x] Task 2: Configure pubspec.yaml (AC: #1, #3)
  - [x] Set package name: `apix`
  - [x] Set description matching GitHub repo description
  - [x] Set SDK constraint: `>=3.0.0 <4.0.0`
  - [x] Add Dio dependency: `dio: ^5.0.0`
  - [x] Add dev dependencies: `flutter_test`, `mocktail`, `flutter_lints`
  - [x] Set homepage to GitHub repo URL
  - [x] Set repository to GitHub repo URL
  
- [x] Task 3: Configure analysis_options.yaml (AC: #2, #3)
  - [x] Include flutter_lints package
  - [x] Add strict analysis rules for pub.dev compliance
  
- [x] Task 4: Create barrel export file (AC: #1)
  - [x] Create lib/apix.dart with library declaration
  - [x] Add placeholder exports (will be populated in future stories)
  
- [x] Task 5: Create initial test (AC: #4)
  - [x] Create test/apix_test.dart with basic import test
  - [x] Verify `flutter test` passes

- [x] Task 6: Verify setup (AC: #3, #4)
  - [x] Run `flutter analyze` - must pass with no issues
  - [x] Run `flutter test` - must pass
  - [x] Run `dart format --set-exit-if-changed .` - must pass

## Dev Notes

### Architecture Requirements

**From architecture.md:**
- Starter: `flutter create --template=package --project-name=apix .`
- Target structure for lib/src/ (to be created in later stories):
  ```
  lib/
  ├── apix.dart (barrel export)
  └── src/
      ├── client/
      ├── interceptors/
      ├── config/
      ├── errors/
      ├── cache/
      ├── models/
      └── utils/
  ```

### Dependencies (from ADRs)

| Dependency | Version | Purpose |
|------------|---------|---------|
| dio | ^5.0.0 | HTTP client transport |
| mocktail | any | Testing mocks |
| flutter_lints | any | Analysis rules |

### Naming Conventions

- Package name: `apix` (lowercase, underscore for multi-word)
- Library: `library apix;`
- Files: snake_case
- Classes: PascalCase

### Project Structure Notes

- This story creates the foundation only
- lib/src/ subdirectories will be created by subsequent stories as needed
- Do NOT create placeholder files for future features

### References

- [Source: architecture.md#Starter Template Evaluation]
- [Source: architecture.md#Implementation Patterns]
- [Source: epics.md#Story 1.1]

## Dev Agent Record

### Agent Model Used

Claude 3.5 Sonnet (Cascade)

### Debug Log References

None

### Completion Notes List

- Flutter package initialized with `flutter create --template=package`
- pubspec.yaml configured with Dio ^5.0.0, mocktail, SDK >=3.0.0
- analysis_options.yaml with strict rules for pub.dev compliance
- All verification passed: analyze, test, format

### File List

- `pubspec.yaml` - Package configuration with dependencies
- `lib/apix.dart` - Barrel export file (placeholder)
- `analysis_options.yaml` - Strict linting rules
- `test/apix_test.dart` - Initial import test
- `README.md` - Generated readme (to be updated in Epic 8)
- `CHANGELOG.md` - Generated changelog
- `LICENSE` - BSD license

### Change Log

- 2026-03-16: Story 1.1 implemented - Package structure initialized
