# Contributing to ApiX

Thank you for your interest in contributing to ApiX! 🎉

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/apix.git
   ```
3. Install dependencies:
   ```bash
   flutter pub get
   ```

## Development Workflow

### Branch Naming

- `epic/{num}-{name}` - Epic branches (e.g., `epic/9-secure-token-storage`)
- `feature/{description}` - Feature branches
- `fix/{description}` - Bug fix branches

### Commit Convention

We follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New feature
- `fix:` Bug fix
- `test:` Adding tests
- `docs:` Documentation
- `chore:` Maintenance
- `refactor:` Code refactoring

Example:
```
feat(auth): add SecureTokenProvider for secure storage
```

### Running Tests

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/auth/auth_interceptor_test.dart
```

### Code Quality

Before submitting a PR:

```bash
# Check formatting
dart format --set-exit-if-changed lib test

# Run analyzer
dart analyze --fatal-infos lib test

# Run tests
flutter test
```

## Pull Request Process

1. Create your feature branch from `develop`
2. Make your changes with appropriate tests
3. Ensure all tests pass and code is formatted
4. Update documentation if needed
5. Submit a PR to `develop`

## Code Style

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart)
- Use dartdoc for public APIs
- Keep functions small and focused
- Prefer immutability

## Questions?

Feel free to open an issue for questions or discussions.

---

Made with ❤️ by [Germinator](https://germinator-space.com)
