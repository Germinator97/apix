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

  /// Creates a [CacheEntry] with the given data and expiration.
  CacheEntry({
    required this.data,
    required this.statusCode,
    required this.createdAt,
    required this.expiresAt,
    this.etag,
    this.headers,
  });

  /// Creates a [CacheEntry] that expires after [ttl] duration.
  factory CacheEntry.withTtl({
    required String data,
    required int statusCode,
    required Duration ttl,
    String? etag,
    Map<String, String>? headers,
  }) {
    final now = DateTime.now();
    return CacheEntry(
      data: data,
      statusCode: statusCode,
      createdAt: now,
      expiresAt: now.add(ttl),
      etag: etag,
      headers: headers,
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
  }) {
    return CacheEntry(
      data: data ?? this.data,
      statusCode: statusCode ?? this.statusCode,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      etag: etag ?? this.etag,
      headers: headers ?? this.headers,
    );
  }

  /// Converts this entry to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'statusCode': statusCode,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      if (etag != null) 'etag': etag,
      if (headers != null) 'headers': headers,
    };
  }

  /// Creates a [CacheEntry] from a JSON map.
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
