// Visible Cloudflare challenge dialog (WAF ladder tier 3, 2026-10-23):
// when the headless WebView cannot auto-solve a site's challenge, the
// user gets this full-screen mini-browser ONCE — tap the checkbox, the
// clearance cookie lands in the shared CookieManager store, the dialog
// pops itself, and the headless WebView (plus the relayed cronet lane)
// takes over from there.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/i18n/i18n.dart';
import '../../core/net/webview_gate.dart' show looksChallenged;

Future<bool> showChallengeDialog(BuildContext context, Uri uri) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChallengeDialog(uri: uri),
  );
  return result ?? false;
}

class _ChallengeDialog extends StatefulWidget {
  const _ChallengeDialog({required this.uri});

  final Uri uri;

  @override
  State<_ChallengeDialog> createState() => _ChallengeDialogState();
}

class _ChallengeDialogState extends State<_ChallengeDialog> {
  Timer? _poll;
  bool _done = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _startPolling(InAppWebViewController controller) {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (_done || !mounted) return;
      try {
        final title = await controller
            .evaluateJavascript(source: 'document.title');
        if (!looksChallenged(title is String ? title : null)) {
          // Second check against the document itself — some challenge
          // shells clear the title before the body.
          final html = await controller.evaluateJavascript(
              source: 'document.documentElement.outerHTML');
          if (!looksChallenged(
              title is String ? title : null, html is String ? html : null)) {
            _done = true;
            if (mounted) Navigator.of(context).pop(true);
          }
        }
      } catch (_) {
        // mid-navigation — next tick retries
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _done = true;
      },
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(t(context, 'waf.challenge_title')),
            actions: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  t(context, 'waf.challenge_hint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest:
                      URLRequest(url: WebUri(widget.uri.toString())),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    incognito: false,
                    cacheEnabled: true,
                    thirdPartyCookiesEnabled: true,
                  ),
                  onLoadStop: (controller, _) => _startPolling(controller),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
