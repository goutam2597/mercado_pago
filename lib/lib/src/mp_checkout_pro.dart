import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'mp_config.dart';
import 'mp_models.dart';
import 'checkout_webview.dart';

/// Mercado Pago Checkout Pro (client-only demo).
/// Flow:
/// 1) POST /checkout/preferences → get preference (init_point/sandbox_init_point)
/// 2) Open WebView to init_point (uses sandbox when test token)
/// 3) On return URL, parse MP params (status, payment_id/collection_id)
/// 4) If payment_id present, GET /v1/payments/{payment_id} to confirm status
class MPCheckoutPro {
  static Future<MPCheckoutResult> startPayment({
    required BuildContext context,
    required MPConfig config,
    required double amount,            // amount per single item
    required String title,             // item title
    required String currencyId,        // e.g., 'BRL', 'ARS', 'CLP', 'MXN', 'USD' (region dependent)
    required String returnUrl,         // custom scheme recommended: myapp://payment-return
    String? description,
    int quantity = 1,
    String? appBarTitle,
    // Optional payer data (improves UX)
    String? payerEmail,
    String? payerFirstName,
    String? payerLastName,
    // Extra preference fields passthrough
    Map<String, dynamic> extraPreference = const {},
  }) async {
    final base = config.apiBase.replaceAll(RegExp(r'/$'), '');

    // 1) Create preference
    final prefUrl = Uri.parse('$base/checkout/preferences');
    final prefBody = {
      'items': [
        {
          'title': title,
          'description': description ?? title,
          'quantity': quantity,
          'currency_id': currencyId,
          'unit_price': amount,
        }
      ],
      // Deep links or https pages; auto_return=approved for quick bounce
      'back_urls': {
        'success': returnUrl,
        'pending': returnUrl,
        'failure': returnUrl,
      },
      'auto_return': 'approved',
      if (payerEmail != null || payerFirstName != null || payerLastName != null)
        'payer': {
          if (payerEmail != null) 'email': payerEmail,
          if (payerFirstName != null) 'name': payerFirstName,
          if (payerLastName != null) 'surname': payerLastName,
        },
      ...extraPreference,
    };

    final createRes = await http.post(
      prefUrl,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.accessToken}',
      },
      body: jsonEncode(prefBody),
    );

    if (config.enableLogs) {
      // ignore: avoid_print
      print('[MP] create pref ${createRes.statusCode} ${createRes.body}');
    }
    if (createRes.statusCode != 201 && createRes.statusCode != 200) {
      throw MPException('Create preference failed: ${createRes.statusCode} ${createRes.body}');
    }

    final pref = jsonDecode(createRes.body) as Map<String, dynamic>;
    final prefId = (pref['id'] ?? '').toString();
    final initPoint = (pref['sandbox_init_point'] ?? pref['init_point'] ?? '').toString();

    if (prefId.isEmpty || initPoint.isEmpty) {
      throw MPException('Invalid preference response: missing id/init_point');
    }

    // 2) Open WebView
    Uri? returned;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutWebView(
          checkoutUrl: initPoint,
          returnUrl: returnUrl,
          onReturn: (uri) => returned = uri,
          appBarTitle: appBarTitle ?? 'Mercado Pago',
        ),
      ),
    );

    // 3) Parse return params
    // Common params (varies by region/version): status, payment_id, collection_id, external_reference, preference_id
    final qp = returned?.queryParameters ?? {};
    final fromUrlPaymentId = (qp['payment_id'] ?? qp['collection_id'] ?? '').toString();
    final urlStatus = (qp['status'] ?? qp['collection_status'] ?? '').toString();

    // Normalize URL-provided status
    String finalStatus = _normalize(urlStatus);

    String? confirmedPaymentId;
    Map<String, dynamic>? paymentGet;

    // 4) If payment id exists, confirm via GET /v1/payments/{id}
    if (fromUrlPaymentId.isNotEmpty) {
      final pUrl = Uri.parse('$base/v1/payments/$fromUrlPaymentId');
      final payRes = await http.get(
        pUrl,
        headers: {'Authorization': 'Bearer ${config.accessToken}'},
      );

      if (config.enableLogs) {
        // ignore: avoid_print
        print('[MP] get payment ${payRes.statusCode} ${payRes.body}');
      }

      if (payRes.statusCode == 200) {
        paymentGet = jsonDecode(payRes.body) as Map<String, dynamic>;
        confirmedPaymentId = (paymentGet['id'] ?? '').toString();
        final mpStatus = (paymentGet['status'] ?? '').toString(); // approved, pending, rejected, in_process
        finalStatus = _normalize(mpStatus);
      }
    }

    return MPCheckoutResult(
      preferenceId: prefId,
      paymentId: confirmedPaymentId!.isNotEmpty == true ? confirmedPaymentId : (fromUrlPaymentId.isNotEmpty ? fromUrlPaymentId : null),
      status: finalStatus,
      raw: {
        'preference': pref,
        'returnUri': returned?.toString(),
        'returnParams': qp,
        if (paymentGet != null) 'paymentGet': paymentGet,
      },
    );
  }

  static String _normalize(String s) {
    final t = s.toLowerCase();
    if (t == 'approved' || t == 'success' || t == 'authorized' || t == 'authorised') return 'SUCCESS';
    if (t == 'rejected' || t.contains('fail') || t == 'cancelled' || t == 'canceled') return 'FAILED';
    if (t == 'pending' || t == 'in_process' || t == 'in_mediation') return 'PENDING';
    return t.isEmpty ? 'PENDING' : 'PENDING';
  }
}
