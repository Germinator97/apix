/// How a response body was turned into the [CacheEntry.data] string, and
/// therefore how it must be turned back.
///
/// A cache entry stores text, so every body has to be encoded on the way in.
/// Recording *which* encoding was used is what keeps a cache hit returning the
/// same runtime type the network returned: without it everything was
/// `jsonEncode`d and `jsonDecode`d, so a `text/plain` body of `12345` came back
/// as the **int** `12345`, and a binary download came back as a
/// `List<dynamic>` instead of bytes — breaking any cast at the call site, on
/// the second request only.
enum CacheBodyEncoding {
  /// A `Map` or `List` stored as JSON.
  json,

  /// A `String` stored verbatim, and returned verbatim — never re-parsed.
  text,

  /// Binary data stored as base64, returned as a `Uint8List`.
  bytes,

  /// A null body.
  empty,
}

/// A cached response entry with metadata.
///
/// Stores the response data along with expiration information
/// for cache invalidation.
class CacheEntry {
  /// The cached response data as JSON string.
  final String data;

  /// The HTTP status code of the cached response.
  final int statusCode;

  /// The timestamp when this entry was created.
  final DateTime createdAt;

  /// The timestamp when this entry expires.
  final DateTime expiresAt;

  /// Optional ETag for conditional requests.
  final String? etag;

  /// Optional response headers to preserve.
  final Map<String, String>? headers;

  /// How [data] was encoded, and therefore how it must be decoded.
  ///
  /// Defaults to [CacheBodyEncoding.json], which is what every entry written
  /// before this field existed used.
  final CacheBodyEncoding encoding;

  /// Creates a [CacheEntry] with the given data and expiration.
  CacheEntry({
    required this.data,
    required this.statusCode,
    required this.createdAt,
    required this.expiresAt,
    this.etag,
    this.headers,
    this.encoding = CacheBodyEncoding.json,
  });

  /// Creates a [CacheEntry] that expires after [ttl] duration.
  factory CacheEntry.withTtl({
    required String data,
    required int statusCode,
    required Duration ttl,
    String? etag,
    Map<String, String>? headers,
    CacheBodyEncoding encoding = CacheBodyEncoding.json,
  }) {
    final now = DateTime.now();
    return CacheEntry(
      data: data,
      statusCode: statusCode,
      createdAt: now,
      expiresAt: now.add(ttl),
      etag: etag,
      headers: headers,
      encoding: encoding,
    );
  }

  /// Returns a copy whose lifetime restarts now, for [ttl].
  ///
  /// Used when a `304 Not Modified` confirms the stored body is still current:
  /// the server has just told us it is fresh, so the entry has to stop being
  /// stale — otherwise every later request revalidates again, forever.
  CacheEntry revalidated({required Duration ttl, String? etag}) {
    final now = DateTime.now();
    return CacheEntry(
      data: data,
      statusCode: statusCode,
      createdAt: now,
      expiresAt: now.add(ttl),
      etag: etag ?? this.etag,
      headers: headers,
      encoding: encoding,
    );
  }

  /// Returns true if this entry has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Returns true if this entry is still valid.
  bool get isValid => !isExpired;

  /// Returns the remaining time until expiration.
  Duration get remainingTtl {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Creates a copy with updated fields.
  CacheEntry copyWith({
    String? data,
    int? statusCode,
    DateTime? createdAt,
    DateTime? expiresAt,
    String? etag,
    Map<String, String>? headers,
    CacheBodyEncoding? encoding,
  }) {
    return CacheEntry(
      data: data ?? this.data,
      statusCode: statusCode ?? this.statusCode,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      etag: etag ?? this.etag,
      headers: headers ?? this.headers,
      encoding: encoding ?? this.encoding,
    );
  }

  /// Converts this entry to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'statusCode': statusCode,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'encoding': encoding.name,
      if (etag != null) 'etag': etag,
      if (headers != null) 'headers': headers,
    };
  }

  /// Reads [encoding] back, tolerating both an entry written before the field
  /// existed and one naming an encoding this version does not know.
  static CacheBodyEncoding _encodingFrom(Object? raw) {
    if (raw is! String) return CacheBodyEncoding.json;
    for (final value in CacheBodyEncoding.values) {
      if (value.name == raw) return value;
    }
    return CacheBodyEncoding.json;
  }

  /// Creates a [CacheEntry] from a JSON map.
  ///
  /// Returns `null` if the data is corrupted or has an unexpected format.
  static CacheEntry? tryFromJson(Map<String, dynamic> json) {
    try {
      return CacheEntry(
        data: json['data'] as String,
        statusCode: json['statusCode'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        etag: json['etag'] as String?,
        headers: json['headers'] != null
            ? Map<String, String>.from(json['headers'] as Map)
            : null,
        encoding: _encodingFrom(json['encoding']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Creates a [CacheEntry] from a JSON map.
  ///
  /// Throws if the data is corrupted. Prefer [tryFromJson] for storage
  /// backends that may contain corrupted data.
  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(
      data: json['data'] as String,
      statusCode: json['statusCode'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      etag: json['etag'] as String?,
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'] as Map)
          : null,
      encoding: _encodingFrom(json['encoding']),
    );
  }

  @override
  String toString() {
    return 'CacheEntry(statusCode: $statusCode, '
        'createdAt: $createdAt, '
        'expiresAt: $expiresAt, '
        'isExpired: $isExpired)';
  }
}
