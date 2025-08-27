enum MPCheckoutEnvStrategy {
  auto,    // default: force sandbox when TEST token, else use init_point
  sandbox, // always sandbox redirect
  prod,    // always production redirect (not recommended with TEST token)
}

class MPConfig {
  /// Mercado Pago Access Token (use TEST-... for sandbox)
  final String accessToken;

  /// Country TLD used to compose sandbox redirect if needed (e.g. 'br','ar','mx','cl')
  /// If null, it will be inferred from currency_id when possible, otherwise 'br'.
  final String? regionTld;

  /// How to choose the checkout URL.
  final MPCheckoutEnvStrategy envStrategy;

  /// Enable console logs
  final bool enableLogs;

  const MPConfig({
    required this.accessToken,
    this.regionTld,
    this.envStrategy = MPCheckoutEnvStrategy.auto,
    this.enableLogs = true,
  });

  bool get isTest => accessToken.startsWith('TEST-');
}

class MPCheckoutResult {
  final String preferenceId;
  final String? paymentId; // client-only demo keeps this null
  /// APPROVED | PENDING | REJECTED | UNKNOWN (we keep it conservative client-side)
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
