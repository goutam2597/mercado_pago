import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'checkout_webview.dart';
import 'mp_models.dart';

class MPCheckoutPro {
  /// Creates a Preference, then opens Checkout (webview or external).
  ///
  /// [returnUrl] should be an HTTPS **back_url** page you control.
  /// That page can immediately `location.replace('myapp://payment-return?...')`
  /// so the app (WebView or deep-link listener) can close itself.
  static Future<MPCheckoutResult> startPayment({
    required BuildContext context,
    required MPConfig config,
    required double amount,
    required String currencyId,     // e.g. 'BRL', 'ARS', 'MXN'
    required String title,
    String description = '',
    String? returnUrl,              // HTTPS recommended
    String? payerEmail,
    MPCheckoutMode mode = MPCheckoutMode.webview,
  }) async {
    final externalRef = 'ORD_${DateTime.now().millisecondsSinceEpoch}';

    // 1) Build preference
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

    // 2) Create preference
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

    final sandboxInit = (body['sandbox_init_point'] ?? '').toString();
    final initPoint   = (body['init_point'] ?? '').toString();

    // 3) Pick correct URL. If TEST token but sandbox URL is missing, force sandbox.
    final checkoutUrl = config.isTest
        ? (sandboxInit.isNotEmpty
        ? sandboxInit
        : 'https://sandbox.mercadopago.com.${config.regionTld}/checkout/v1/redirect?pref_id=$prefId')
        : (initPoint.isNotEmpty ? initPoint : sandboxInit);

    if (config.enableLogs) {
      // ignore: avoid_print
      print('[MP] using URL: $checkoutUrl (mode=$mode)');
    }

    Uri? returned;

    if (mode == MPCheckoutMode.webview) {
      // 4A) Open inside the app
      final targets = <Uri>[];
      if (returnUrl != null && returnUrl.isNotEmpty) {
        targets.add(Uri.parse(returnUrl));
      }

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
    } else {
      // 4B) Launch external browser / native app, rely on deep-link back
      final uri = Uri.parse(checkoutUrl);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw MPException('Could not launch checkout URL');
      }
      // In external mode, you should listen for your deep link in the app code
      // (e.g., via `uni_links`). The package can’t capture it here. We still
      // return a PENDING placeholder result below.
    }

    // Client-only demo → conservative status. For production, use webhooks.
    return MPCheckoutResult(
      preferenceId: prefId,
      paymentId: null,
      status: 'PENDING',
      raw: {
        'preference': body,
        'external_reference': externalRef,
        'returnUri': returned?.toString(),
        'checkoutUrlUsed': checkoutUrl,
        'mode': mode.name,
      },
    );
  }
}
