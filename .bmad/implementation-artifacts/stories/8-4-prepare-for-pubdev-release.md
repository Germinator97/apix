# Story 8.4: Prepare for pub.dev Release

Status: done

## Story

As a package maintainer,
I want to prepare the package for pub.dev publication,
So that developers can easily install and use it.

## Acceptance Criteria

1. **Given** the package files
   - **When** running `flutter pub publish --dry-run`
   - **Then** validation passes with no errors

2. **Given** the repository
   - **When** viewing on GitHub
   - **Then** CI workflow runs on push/PR

## Tasks

- [x] Fix CI badge URL in README (ci.yml → ci.yaml)
- [x] Add MIT LICENSE content
- [x] Create CONTRIBUTING.md
- [x] Validate with `flutter pub publish --dry-run`

## Notes

Package validated and ready for publication. CI workflow already exists at `.github/workflows/ci.yaml`.
