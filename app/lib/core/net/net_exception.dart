/// Typed network-layer exception (Plan/01 §8 error convention).
class NetException implements Exception {
  const NetException(this.message, {this.uri, this.statusCode});

  final String message;
  final Uri? uri;
  final int? statusCode;

  @override
  String toString() =>
      'NetException: $message${uri != null ? ' ($uri)' : ''}'
      '${statusCode != null ? ' [HTTP $statusCode]' : ''}';
}
