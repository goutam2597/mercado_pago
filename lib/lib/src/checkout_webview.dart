import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

typedef ReturnHandler = void Function(Uri uri);

/// Opens Checkout Pro inside a WebView.
/// If you provide an HTTPS [returnTargets] page (your "bounce" page),
/// this widget intercepts it and closes automatically.
class CheckoutWebView extends StatefulWidget {
  final String checkoutUrl;
  final List<Uri> returnTargets; // usually your HTTPS bounce page(s)
  final ReturnHandler onReturn;
  final String? title;

  const CheckoutWebView({
    super.key,
    required this.checkoutUrl,
    required this.returnTargets,
    required this.onReturn,
    this.title,
  });

  @override
  State<CheckoutWebView> createState() => _CheckoutWebViewState();
}

class _CheckoutWebViewState extends State<CheckoutWebView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri != null && _isReturnUrl(uri)) {
              widget.onReturn(uri);
              if (mounted) Navigator.of(context).pop();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  bool _isReturnUrl(Uri u) {
    for (final t in widget.returnTargets) {
      final exact = u.scheme == t.scheme && u.host == t.host && u.path == t.path;
      final prefix = u.toString().startsWith(t.toString());
      if (exact || prefix) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Mercado Pago')),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}
