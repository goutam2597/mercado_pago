enum MPCheckoutEnvStrategy {
  auto,     // If token starts with TEST- → sandbox; else production
  sandbox,  // Always sandbox redirect
  prod,     // Always production redirect (use only with real Access Token)
}

class MPConfig {
  /// Mercado Pago Access Token.
  /// - TEST-... for sandbox
  /// - APP_USR-... for production
  final String accessToken;

  /// Country TLD used to compose sandbox redirect (if needed).
  /// 'br','ar','mx','cl','co','pe','uy'
  final String regionTld;

  /// How to choose the checkout URL.
  final MPCheckoutEnvStrategy envStrategy;

  /// Enable console logs
  final bool enableLogs;

  const MPConfig({
    required this.accessToken,
    this.regionTld = 'br',
    this.envStrategy = MPCheckoutEnvStrategy.auto,
    this.enableLogs = true,
  });

  bool get isTest => accessToken.startsWith('TEST-');
}

class MPCheckoutResult {
  final String preferenceId;
  final String? paymentId; // not resolved client-side in this demo
  /// APPROVED | PENDING | REJECTED | UNKNOWN (client-only fallback)
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
