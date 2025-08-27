import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

typedef ReturnHandler = void Function(Uri uri);

class CheckoutWebView extends StatefulWidget {
  final String checkoutUrl;
  final List<Uri> returnTargets; // HTTPS bounce page(s) you control (optional)
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
  bool _alreadyHandledBlock = false;

  @override
  void initState() {
    super.initState();

    // Create platform params (no .instance on WebKit)
    PlatformWebViewControllerCreationParams params =
    const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) async {
            setState(() => _loading = false);
            await _detectAndHandleBlockedMerchant();
          },
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
      );

    // Android extras
    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      platformController.setMediaPlaybackRequiresUserGesture(false);
      platformController.setJavaScriptMode(JavaScriptMode.unrestricted);
    }

    controller.loadRequest(Uri.parse(widget.checkoutUrl));
    _controller = controller;
  }

  bool _isReturnUrl(Uri u) {
    for (final t in widget.returnTargets) {
      final exact = u.scheme == t.scheme && u.host == t.host && u.path == t.path;
      final prefix = u.toString().startsWith(t.toString());
      if (exact || prefix) return true;
    }
    return false;
  }

  /// Hide MP "merchant cannot receive payments" page (pt/es/en variants).
  Future<void> _detectAndHandleBlockedMerchant() async {
    if (_alreadyHandledBlock) return;
    try {
      final title = (await _controller.getTitle())?.toLowerCase() ?? '';
      final bodyTextRaw = await _controller
          .runJavaScriptReturningResult('document.body && document.body.innerText || ""');
      final bodyText = bodyTextRaw is String
          ? bodyTextRaw.toLowerCase()
          : bodyTextRaw.toString().toLowerCase();

      const needles = <String>[
        'não pode receber pagamentos',
        'nao pode receber pagamentos',
        'no momento, popular na internet não pode receber pagamentos',
        'no momento, popular na internet nao pode receber pagamentos',
        'no puede recibir pagos',
        'can’t receive payments',
        'cant receive payments',
        'cannot receive payments',
      ];

      final hit = needles.any((s) => title.contains(s) || bodyText.contains(s));
      if (hit) {
        _alreadyHandledBlock = true;
        final synthetic = Uri.parse(
          'myapp://payment-return?status=rejected&reason=merchant_not_enabled',
        );
        widget.onReturn(synthetic);
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      // ignore
    }
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
