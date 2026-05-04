# Story 12.3: Add SSL pinning support via certificatePins config

Status: ready-for-dev

## Story

As a developer,
I want to pin SSL certificates by SHA-256 fingerprint via `ApiClientConfig.certificatePins`,
so that MITM attacks are blocked in fintech apps where Dio's default OS trust store isn't tight enough.

## Context (why)

an internal app, a consumer and an internal app all process sensitive financial data. The OS trust store includes ~150 root CAs — any compromised CA can issue valid certs for our domain. SSL pinning shrinks the trust set to a known list of public-key fingerprints we control.

Implementing this manually with `dio.httpClientAdapter` requires boilerplate that's easy to get wrong (wrong hash algorithm, comparing the wrong certificate in the chain, forgetting to handle key rotation). Built-in support reduces the surface for mistakes.

## Acceptance Criteria

1. **Given** `ApiClientConfig(certificatePins: ['<sha256-hex-1>', '<sha256-hex-2>'])`
   **When** an HTTPS request is sent
   **Then** the server's leaf certificate SHA-256 is computed
   **And** if it matches **any** pin in the list → request proceeds
   **And** if it matches **none** → `CertificatePinException` is thrown (extends `NetworkException`)

2. **Given** an empty list `certificatePins: []`
   **When** a request is sent
   **Then** standard OS trust validation is used (no pinning — backward compatible default)

3. **Given** multiple pins (key rotation scenario)
   **When** any pin matches
   **Then** request proceeds (allows seamless cert rotation)

4. **Given** `CertificatePinException`
   **Then** it extends `NetworkException`
   **And** `serverFingerprint` (computed) and `expectedPins` (configured) are accessible
   **And** `message` is human-readable for logging

5. **Platform support:** Flutter mobile (iOS, Android) and desktop. **Web is excluded** — browser controls TLS, pinning is impossible. Document this limitation.

6. **Given** the app runs on Web with `certificatePins` configured
   **Then** the package logs a warning (once per `ApiClient` lifetime) and **does not** apply pinning (degrades gracefully)

## Tasks / Subtasks

- [ ] Task 1: Create `CertificatePinException`
  - [ ] New file `lib/src/errors/certificate_pin_exception.dart`
  - [ ] Extends `NetworkException`
  - [ ] Fields: `serverFingerprint` (String), `expectedPins` (List<String>)

- [ ] Task 2: Add `certificatePins` to `ApiClientConfig`
  - [ ] `final List<String>? certificatePins;`
  - [ ] Stored as lowercase hex (normalize on construction)
  - [ ] Update `copyWith`

- [ ] Task 3: Custom `HttpClientAdapter` with pinning
  - [ ] Use conditional imports for platform separation:
    - [ ] `dart.library.io` → mobile/desktop implementation
    - [ ] `dart.library.html` → web no-op + warning
  - [ ] Mobile/desktop: subclass `IOHttpClientAdapter`, inject `badCertificateCallback` that returns `false` and throw `CertificatePinException` from a pre-flight check, OR use `SecurityContext` + `setTrustedCertificatesBytes`
  - [ ] Recommended approach: extract the leaf cert from `HttpClient`'s connection callback, compute SHA-256, compare to pins
  - [ ] Wire into `ApiClientFactory.create` if `certificatePins` is set

- [ ] Task 4: Helper to extract pins from a cert (developer ergonomics)
  - [ ] CLI snippet in README: `openssl s_client -connect api.example.com:443 -servername api.example.com </dev/null 2>/dev/null | openssl x509 -fingerprint -sha256 -noout | tr -d ':' | tr 'A-Z' 'a-z'`

- [ ] Task 5: Unit tests
  - [ ] Mock `HttpClient` with a known cert → verify match/mismatch
  - [ ] Empty pins → no pinning applied (regression)
  - [ ] Web platform → warning logged, no pinning enforced
  - [ ] Multiple pins, second one matches → success
  - [ ] No pins match → `CertificatePinException` with correct fields

- [ ] Task 6: Documentation
  - [ ] README: dedicated section with security rationale + CLI snippet to extract pins
  - [ ] Note on cert rotation: always pin **two** certificates (current + next)

## Dev Notes

### Why this can be tricky

- `IOHttpClientAdapter.badCertificateCallback` only fires when the OS chain is invalid. When the server's cert is signed by a trusted CA, the callback is bypassed. We need to hook **before** that — typically via `HttpClient.connectionFactory` or by wrapping `SecureSocket.connect`.
- An alternative approach: pin the **public key** (SPKI) rather than the cert. SPKI pins survive cert rotations as long as the key stays the same. **Recommend SPKI** for the implementation but document both options.

### Public key (SPKI) vs cert fingerprint

| Approach | Pros | Cons |
|----------|------|------|
| Cert SHA-256 | Simple, what `openssl x509 -fingerprint` outputs | Breaks on every cert renewal |
| SPKI SHA-256 | Survives cert renewal as long as key stays same | Slightly more involved to extract |

Recommendation: support both, accept either form in `certificatePins`, auto-detect by length (cert fingerprints are typically the value of `-fingerprint -sha256`, displayed colon-separated; SPKI is hex too — may need explicit prefix like `cert-sha256:` / `spki-sha256:`).

### Decision deferred

Final algorithm choice (SPKI vs cert) — to be decided at implementation time after a quick spike. Document the chosen approach in CHANGELOG and README.

### References

- Brainstorming `[Fail #10]` — *"SSL invalide → allowBadCertificates + pinning"*
- OWASP Mobile Top 10 (M3 — insufficient communication security)
- Dio docs on `HttpClientAdapter`

## Dev Agent Record

### File List (Target)

- `lib/src/errors/certificate_pin_exception.dart` — new
- `lib/src/client/api_client_config.dart` — add field
- `lib/src/client/pinning/pinning_adapter_io.dart` — new (mobile/desktop)
- `lib/src/client/pinning/pinning_adapter_web.dart` — new (no-op + warn)
- `lib/src/client/pinning/pinning_adapter.dart` — conditional export
- `lib/src/client/api_client_factory.dart` — wire adapter
- `test/client/pinning_test.dart` — new
- `README.md` — security section
