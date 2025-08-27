import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'checkout_webview.dart';
import 'mp_models.dart';

class MPCheckoutPro {
  /// Create a preference → pick proper checkout URL → open in WebView.
  ///
  /// [returnUrl] should be an HTTPS page you control that (optionally) bounces to
  /// a custom scheme so the WebView can auto-close:
  ///   location.replace('myapp://payment-return?status=' + encodeURIComponent(status));
  static Future<MPCheckoutResult> startPayment({
    required BuildContext context,
    required MPConfig config,
    required double amount,
    required String currencyId,  // 'BRL','ARS','MXN','CLP','CO','PE','UY'
    required String title,
    String description = '',
    String? returnUrl,           // HTTPS recommended; optional
    String? payerEmail,
  }) async {
    final externalRef = 'ORD_${DateTime.now().millisecondsSinceEpoch}';

    // Build preference payload
    final payload = {
      'items': [
        {
          'title': title,
          'description': description,
          'quantity': 1,
          'currency_id': currencyId,
          'unit_price': amount,
        }
      ],
      'external_reference': externalRef,
      if (payerEmail != null) 'payer': {'email': payerEmail},
      if (returnUrl != null && returnUrl.startsWith('http'))
        'back_urls': {'success': returnUrl, 'pending': returnUrl, 'failure': returnUrl},
      if (returnUrl != null && returnUrl.startsWith('http')) 'auto_return': 'approved',
    };

    // Create preference
    final createRes = await http.post(
      Uri.parse('https://api.mercadopago.com/checkout/preferences'),
      headers: {
        'Authorization': 'Bearer ${config.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (config.enableLogs) {
      // ignore: avoid_print
      print('[MP] create ${createRes.statusCode} ${createRes.body}');
    }

    if (createRes.statusCode != 201 && createRes.statusCode != 200) {
      throw MPException('Preference create failed: ${createRes.statusCode} ${createRes.body}');
    }

    final body = jsonDecode(createRes.body) as Map<String, dynamic>;
    final prefId = (body['id'] ?? '').toString();
    if (prefId.isEmpty) throw MPException('Missing preference id');

    final sandboxInit = (body['sandbox_init_point'] ?? '').toString();
    final initPoint   = (body['init_point'] ?? '').toString();

    // Choose checkout URL per strategy + token type
    final checkoutUrl = _chooseCheckoutUrl(
      sandboxInitPoint: sandboxInit,
      initPoint: initPoint,
      prefId: prefId,
      isTestToken: config.isTest,
      regionTld: config.regionTld,
      strategy: config.envStrategy,
    );

    if (config.enableLogs) {
      // ignore: avoid_print
      print('[MP] using URL: $checkoutUrl');
    }

    // Open WebView & optionally intercept returnUrl
    final targets = <Uri>[];
    if (returnUrl != null && returnUrl.isNotEmpty) {
      targets.add(Uri.parse(returnUrl));
    }

    Uri? returned;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutWebView(
          checkoutUrl: checkoutUrl,
          returnTargets: targets,
          onReturn: (uri) => returned = uri,
          title: 'Mercado Pago',
        ),
      ),
    );

    // Client-only demo → conservative PENDING result (use webhooks in prod)
    return MPCheckoutResult(
      preferenceId: prefId,
      paymentId: null,
      status: 'PENDING',
      raw: {
        'preference': body,
        'external_reference': externalRef,
        'returnUri': returned?.toString(),
        'checkoutUrlUsed': checkoutUrl,
      },
    );
  }

  static String _chooseCheckoutUrl({
    required String sandboxInitPoint,
    required String initPoint,
    required String prefId,
    required bool isTestToken,
    required String regionTld,
    required MPCheckoutEnvStrategy strategy,
  }) {
    switch (strategy) {
      case MPCheckoutEnvStrategy.sandbox:
        return _sandboxRedirect(prefId, regionTld);
      case MPCheckoutEnvStrategy.prod:
        return initPoint.isNotEmpty ? initPoint : sandboxInitPoint;
      case MPCheckoutEnvStrategy.auto:
      default:
        if (isTestToken) {
          // Keep it in sandbox to avoid the production-block screen
          return sandboxInitPoint.isNotEmpty ? sandboxInitPoint : _sandboxRedirect(prefId, regionTld);
        }
        // Live token → prefer production init_point
        return initPoint.isNotEmpty ? initPoint : (sandboxInitPoint.isNotEmpty ? sandboxInitPoint : _sandboxRedirect(prefId, regionTld));
    }
  }

  static String _sandboxRedirect(String prefId, String regionTld) =>
      'https://sandbox.mercadopago.com.$regionTld/checkout/v1/redirect?pref_id=$prefId';
}
