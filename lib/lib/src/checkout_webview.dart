import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

typedef ReturnHandler = void Function(Uri uri);

/// Opens [checkoutUrl] and intercepts [returnUrl] (custom scheme or https).
class CheckoutWebView extends StatefulWidget {
  final String checkoutUrl;
  final String returnUrl;
  final ReturnHandler onReturn;
  final String? appBarTitle;

  const CheckoutWebView({
    super.key,
    required this.checkoutUrl,
    required this.returnUrl,
    required this.onReturn,
    this.appBarTitle,
  });

  @override
  State<CheckoutWebView> createState() => _CheckoutWebViewState();
}

class _CheckoutWebViewState extends State<CheckoutWebView> {
  late final WebViewController _controller;
  late final Uri _target;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _target = Uri.parse(widget.returnUrl);

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
    final customMatch = (u.scheme == _target.scheme) && (u.host == _target.host);
    final httpsMatch =
    (u.scheme == 'https' && _target.scheme == 'https' && u.host == _target.host && u.path == _target.path);
    final prefix = u.toString().startsWith(widget.returnUrl);
    return customMatch || httpsMatch || prefix;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.appBarTitle ?? 'Checkout')),
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
