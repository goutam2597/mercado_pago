enum MPCheckoutMode { webview, external } // external = url_launcher

class MPConfig {
  /// Mercado Pago Access Token (use TEST-... for sandbox)
  final String accessToken;

  /// Country TLD used if we need to force sandbox URL (e.g., 'br', 'ar', 'mx')
  final String regionTld;

  /// Enable log prints
  final bool enableLogs;

  const MPConfig({
    required this.accessToken,
    this.regionTld = 'br',
    this.enableLogs = true,
  });

  bool get isTest => accessToken.startsWith('TEST-');
}

class MPCheckoutResult {
  final String preferenceId;
  final String? paymentId;
  /// APPROVED | PENDING | REJECTED | UNKNOWN  (client-only: conservative)
  final String status;
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
