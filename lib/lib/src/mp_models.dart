class MPCheckoutResult {
  /// The preference id used.
  final String preferenceId;

  /// Mercado Pago payment id if available (from return URL or confirmation call).
  final String? paymentId;

  /// SUCCESS | FAILED | PENDING | CANCELED
  final String status;

  /// Raw snapshots for debugging.
  final Map<String, dynamic> raw;

  const MPCheckoutResult({
    required this.preferenceId,
    required this.status,
    required this.raw,
    this.paymentId,
  });

  bool get isSuccess => status.toUpperCase() == 'SUCCESS';
}

class MPException implements Exception {
  final String message;
  final Object? cause;
  MPException(this.message, [this.cause]);
  @override
  String toString() => 'MPException: $message';
}
