import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'checkout_webview.dart';
import 'mp_models.dart';

class MPCheckoutPro {
  static Future<MPCheckoutResult> startPayment({
    required BuildContext context,
    required MPConfig config,
    required double amount,
    required String currencyId,   // e.g., 'BRL','ARS','MXN'
    required String title,
    String description = '',
    String? returnUrl,            // HTTPS bounce page recommended
    String? payerEmail,
  }) async {
    final externalRef = 'ORD_${DateTime.now().millisecondsSinceEpoch}';

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
        'back_urls': {
          'success': returnUrl,
          'pending': returnUrl,
          'failure': returnUrl,
        },
      if (returnUrl != null && returnUrl.startsWith('http'))
        'auto_return': 'approved',
    };

    // 1) Create preference
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
      throw MPException('Create failed: ${createRes.statusCode} ${createRes.body}');
    }

    final body = jsonDecode(createRes.body) as Map<String, dynamic>;
    final prefId = (body['id'] ?? '').toString();
    if (prefId.isEmpty) throw MPException('Missing preference id');

    // 2) Choose the correct checkout URL
    final sandboxInit = (body['sandbox_init_point'] ?? '').toString();
    final initPoint   = (body['init_point'] ?? '').toString();
    final isTestToken = config.accessToken.startsWith('TEST-');

    final checkoutUrl = isTestToken
        ? (sandboxInit.isNotEmpty
        ? sandboxInit
        : _forceSandboxRedirect(prefId, regionTld: _regionTldFromTokenOrConfig(config)))
        : (initPoint.isNotEmpty ? initPoint : sandboxInit);

    if (config.enableLogs) {
      // ignore: avoid_print
      print('[MP] using URL: $checkoutUrl');
    }

    // 3) Open Checkout Pro and (optionally) intercept back_urls
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

    // We don’t query payments here (client-only demo). Result is conservative.
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

  /// Build a sandbox redirect URL from pref_id + region TLD.
  static String _forceSandboxRedirect(String prefId, {required String regionTld}) {
    // Example: https://sandbox.mercadopago.com.br/checkout/v1/redirect?pref_id=XYZ
    return 'https://sandbox.mercadopago.com.$regionTld/checkout/v1/redirect?pref_id=$prefId';
  }

  /// Use the config.region if you add it to MPConfig later; for now default to 'br'.
  static String _regionTldFromTokenOrConfig(MPConfig config) {
    // If you extend MPConfig with `region`, return it here. Defaulting to Brazil TLD:
    return 'br';
  }
}
