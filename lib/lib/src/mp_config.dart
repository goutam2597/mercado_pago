/// Mercado Pago v1 config (Checkout Pro)
class MPConfig {
  /// API base; default production. For sandbox you still use prod host with test creds.
  final String apiBase;

  /// Your **access token** (TEST-... for sandbox).
  final String accessToken;

  /// Optional: your public key (not required for this flow).
  final String? publicKey;

  /// Enable console logs.
  final bool enableLogs;

  const MPConfig({
    this.apiBase = 'https://api.mercadopago.com',
    required this.accessToken,
    this.publicKey,
    this.enableLogs = true,
  });
}
