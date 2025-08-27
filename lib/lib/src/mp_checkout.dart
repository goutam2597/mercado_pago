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
    required String currencyId,
    required String title,
    String description = '',
    String? returnUrl, // HTTPS bounce page recommended
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

    final createRes = await http.post(
      Uri.parse('https://api.mercadopago.com/checkout/preferences'),
      headers: {
        'Authorization': 'Bearer ${config.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (config.enableLogs) {
      print('[MP] create ${createRes.statusCode} ${createRes.body}');
    }

    if (createRes.statusCode != 201 && createRes.statusCode != 200) {
      throw MPException('Create failed: ${createRes.statusCode} ${createRes.body}');
    }

    final body = jsonDecode(createRes.body) as Map<String, dynamic>;
    final prefId = (body['id'] ?? '').toString();
    final checkoutUrl = (body['sandbox_init_point'] ?? body['init_point']).toString();

    Uri? returned;
    if (returnUrl != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CheckoutWebView(
            checkoutUrl: checkoutUrl,
            returnTargets: [Uri.parse(returnUrl)],
            onReturn: (uri) => returned = uri,
            title: 'Mercado Pago',
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CheckoutWebView(
            checkoutUrl: checkoutUrl,
            returnTargets: const [],
            onReturn: (_) {},
            title: 'Mercado Pago',
          ),
        ),
      );
    }

    return MPCheckoutResult(
      preferenceId: prefId,
      paymentId: null, // optional: implement /v1/payments/search for real id
      status: 'PENDING', // we don’t know yet; use webhooks in production
      raw: {
        'preference': body,
        'external_reference': externalRef,
        'returnUri': returned?.toString(),
      },
    );
  }
}
