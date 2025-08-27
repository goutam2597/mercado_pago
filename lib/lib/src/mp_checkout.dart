import 'package:flutter/material.dart';
import 'checkout_webview.dart';
import 'mp_models.dart';

/// Client-only Checkout Pro opener for a pre-created preference.
/// Supply either a full init URL or a `prefId` (we'll compose a redirect URL).
class MPCheckoutHosted {
  /// Open Checkout Pro.
  ///
  /// [region] affects the domain used if you pass only `prefId`.
  /// Examples:
  ///   'br' -> sandbox.mercadopago.com.br
  ///   'ar' -> sandbox.mercadopago.com.ar
  ///   'mx' -> sandbox.mercadopago.com.mx
  static Future<MPCheckoutResult> open({
    required BuildContext context,
    String? initUrl,             // full URL like sandbox_init_point/init_point
    String? prefId,              // e.g., "TEST-1234-...-..."; if set, we build URL
    String region = 'br',        // country TLD for redirect domain
    String? appBarTitle,
    required List<String> backUrls, // success/pending/failure (https)
  }) async {
    assert(
    initUrl != null || prefId != null,
    'Provide either initUrl or prefId',
    );

    // Build a redirect URL if only prefId is provided.
    // Official docs show query key 'pref_id'. Some logs show 'preference-id'.
    // We'll prefer 'pref_id' and still accept the other on arrival.
    final checkoutUrl = initUrl ??
        'https://sandbox.mercadopago.com.$region/checkout/v1/redirect?pref_id=$prefId';

    // Prepare return targets
    final targets = backUrls
        .where((s) => s.isNotEmpty)
        .map((s) => Uri.parse(s))
        .toList(growable: false);

    Uri? returned;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutWebView(
          checkoutUrl: checkoutUrl,
          returnTargets: targets,
          onReturn: (uri) => returned = uri,
          title: appBarTitle ?? 'Mercado Pago',
        ),
      ),
    );

    final uri = returned;
    final qp = Map<String, String>.from(uri?.queryParameters ?? {});

    // Try both keys we’ve seen in the wild:
    final prefIdFromUrl = qp['pref_id'] ?? qp['preference-id'] ?? prefId;

    // Common return params (varies by method/region; map conservatively):
    // - collection_status: approved / pending / rejected / null
    // - status: approved / pending / failure
    // - payment_id / collection_id
    final rawStatus =
    (qp['collection_status'] ?? qp['status'] ?? 'unknown').toString();
    final normalized = _normalizeStatus(rawStatus);

    final paymentId = qp['payment_id'] ?? qp['collection_id'];

    return MPCheckoutResult(
      status: normalized,
      paymentId: paymentId,
      preferenceId: prefIdFromUrl,
      params: qp,
      returnUri: uri?.toString(),
    );
  }

  static String _normalizeStatus(String s) {
    final t = s.toLowerCase();
    if (t.contains('approved') || t == 'success' || t == 'approved') return 'APPROVED';
    if (t.contains('pending')) return 'PENDING';
    if (t.contains('rejected') || t.contains('failure') || t.contains('failed')) return 'REJECTED';
    return 'UNKNOWN';
  }
}
