import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'checkout_webview.dart';
import 'mp_models.dart';

class MPCheckoutPro {
  /// Create a preference → open Checkout Pro in a WebView.
  ///
  /// [currencyId] examples: 'ARS','BRL','MXN','CLP','COP','PEN','UYU','PYG', ...
  /// [returnUrl] should be an HTTPS page you control; it may bounce to a custom
  /// scheme so the WebView can auto-close, e.g.:
  ///   location.replace('myapp://payment-return?status=' + encodeURIComponent(status));
  static Future<MPCheckoutResult> startPayment({
    required BuildContext context,
    required MPConfig config,
    required double amount,
    required String currencyId,
    required String title,
    String description = '',
    String? returnUrl, // HTTPS recommended; optional
    String? payerEmail,
  }) async {
    final externalRef = 'ORD_${DateTime.now().millisecondsSinceEpoch}';

    // 1) Build preference payload
    final payload = {
      'items': [
        {
          'title': title,
          'description': description,
          'quantity': 1,
          'currency_id': currencyId,
          'unit_price': amount,
        },
      ],
      'external_reference': externalRef,
      if (payerEmail != null) 'payer': {'email': payerEmail},
      if (returnUrl != null && returnUrl.startsWith('http'))
        'back_urls': {
          'success': returnUrl,
          'pending': returnUrl,
          'failure': returnUrl,
        },
      if (returnUrl != null && returnUrl.startsWith('http'))
        'auto_return': 'approved',
    };

    // 2) Create preference (server-side token!)
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
      throw MPException(
        'Preference create failed: ${createRes.statusCode} ${createRes.body}',
      );
    }

    final body = jsonDecode(createRes.body) as Map<String, dynamic>;
    final prefId = (body['id'] ?? '').toString();
    if (prefId.isEmpty) throw MPException('Missing preference id');

    final sandboxInit = (body['sandbox_init_point'] ?? '').toString();
    final initPoint = (body['init_point'] ?? '').toString();

    // 3) Choose the best checkout URL
    final checkoutUrl = _chooseCheckoutUrl(
      sandboxInitPoint: sandboxInit,
      initPoint: initPoint,
      prefId: prefId,
      isTestToken: config.isTest,
      strategy: config.envStrategy,
    );

    if (config.enableLogs) {
      // ignore: avoid_print
      print('[MP] using URL: $checkoutUrl');
    }

    // 4) Open WebView & optionally intercept returnUrl
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

    // In real apps, confirm via webhooks or Payments API.
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

  /// Safer URL picker:
  /// - With test tokens, prefer `init_point` (works in sandbox), fallback to sandbox_init_point.
  /// - With live tokens, use `init_point`, fallback to sandbox_init_point.
  /// - Only if both missing, synthesize a sandbox redirect as last resort.
  static String _chooseCheckoutUrl({
    required String sandboxInitPoint,
    required String initPoint,
    required String prefId,
    required bool isTestToken,
    required MPCheckoutEnvStrategy strategy,
  }) {
    String? pick;

    switch (strategy) {
      case MPCheckoutEnvStrategy.sandbox:
        pick = sandboxInitPoint.isNotEmpty ? sandboxInitPoint : initPoint;
        break;
      case MPCheckoutEnvStrategy.prod:
        pick = initPoint.isNotEmpty ? initPoint : sandboxInitPoint;
        break;
      case MPCheckoutEnvStrategy.auto:
        if (isTestToken) {
          // Test token → prefer init_point (stable in WebView), otherwise sandbox.
          pick = initPoint.isNotEmpty ? initPoint : sandboxInitPoint;
        } else {
          pick = initPoint.isNotEmpty ? initPoint : sandboxInitPoint;
        }
    }

    if (pick.isEmpty) {
      // Last-chance fallback: build a sandbox redirect if the API didn’t return links.
      // NOTE: prefer not to rely on this—MP may change paths. Argentina example shown.
      pick =
          'https://sandbox.mercadopago.com.ar/checkout/v1/redirect?pref_id=$prefId';
    }

    return pick;
  }
}
