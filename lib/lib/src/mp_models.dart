class MPConfig {
  /// Mercado Pago Access Token (use TEST-... token for sandbox)
  final String accessToken;

  /// Enable console logs
  final bool enableLogs;

  const MPConfig({
    required this.accessToken,
    this.enableLogs = true,
  });
}

class MPCheckoutResult {
  final String preferenceId;
  final String? paymentId;
  final String status; // APPROVED | PENDING | REJECTED | UNKNOWN
  final Map<String, dynamic> raw;

  const MPCheckoutResult({
    required this.preferenceId,
    required this.status,
    required this.raw,
    this.paymentId,
  });

  bool get isApproved => status.toUpperCase() == 'APPROVED';
}

class MPException implements Exception {
  final String message;
  final Object? cause;
  MPException(this.message, [this.cause]);
  @override
  String toString() => 'MPException: $message';
}
