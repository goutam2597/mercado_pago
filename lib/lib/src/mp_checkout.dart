import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'checkout_webview.dart';
import 'mp_models.dart';

class MPCheckoutPro {
  /// Create a preference → choose correct checkout URL (sandbox if TEST token) → open in WebView.
  ///
  /// [returnUrl] should be an HTTPS page you control that immediately bounces to your
  /// app deep link if you want the WebView to auto-close:
  ///   <script>
  ///     const q = new URLSearchParams(location.search);
  ///     const s = q.get('status') || q.get('collection_status') || 'pending';
  ///     location.replace('myapp://payment-return?status=' + encodeURIComponent(s));
  ///   </script>
  static Future<MPCheckoutResult> startPayment({
    required BuildContext context,
    required MPConfig config,
    required double amount,
    required String currencyId,  // 'BRL','ARS','MXN','CLP', etc.
    required String title,
    String description = '',
    String? returnUrl,           // HTTPS recommended; optional
    String? payerEmail,
  }) async {
    final externalRef = 'ORD_${DateTime.now().millisecondsSinceEpoch}';

    // --- Build preference payload
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

    // --- Create preference
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

    // --- Choose the correct checkout URL to avoid the prod error screen
    final region = config.regionTld ?? _tldForCurrency(currencyId) ?? 'br';
    final checkoutUrl = _chooseCheckoutUrl(
      sandboxInitPoint: sandboxInit,
      initPoint: initPoint,
      prefId: prefId,
      isTestToken: config.isTest,
      regionTld: region,
      strategy: config.envStrategy,
    );

    if (config.enableLogs) {
      // ignore: avoid_print
      print('[MP] using URL: $checkoutUrl');
    }

    // --- Open Checkout Pro in WebView & optionally intercept returnUrl
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

    // Client-only demo → conservative status
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
    if (strategy == MPCheckoutEnvStrategy.sandbox) {
      return _forceSandboxRedirect(prefId, regionTld);
    }
    if (strategy == MPCheckoutEnvStrategy.prod) {
      return initPoint.isNotEmpty ? initPoint : sandboxInitPoint;
    }

    // auto:
    if (isTestToken) {
      // Prefer API-provided sandbox URL; otherwise force sandbox to avoid prod error.
      return sandboxInitPoint.isNotEmpty
          ? sandboxInitPoint
          : _forceSandboxRedirect(prefId, regionTld);
    }
    // Access token is live → prefer production init_point.
    return initPoint.isNotEmpty ? initPoint : (sandboxInitPoint.isNotEmpty ? sandboxInitPoint : _forceSandboxRedirect(prefId, regionTld));
  }

  static String _forceSandboxRedirect(String prefId, String regionTld) {
    // Example: https://sandbox.mercadopago.com.br/checkout/v1/redirect?pref_id=XYZ
    return 'https://sandbox.mercadopago.com.$regionTld/checkout/v1/redirect?pref_id=$prefId';
  }

  static String? _tldForCurrency(String currency) {
    switch (currency.toUpperCase()) {
      case 'BRL': return 'br';
      case 'ARS': return 'ar';
      case 'MXN': return 'mx';
      case 'CLP': return 'cl';
      case 'COP': return 'co';
      case 'PEN': return 'pe';
      case 'UYU': return 'uy';
      default:    return null;
    }
  }
}
