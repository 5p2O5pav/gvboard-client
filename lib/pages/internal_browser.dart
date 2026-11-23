import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

class InternalBrowserPage extends StatefulWidget {
  const InternalBrowserPage({
    required this.url,
    this.title = '支付页面',
    super.key,
  });

  final String url;
  final String title;

  static Future<void> open(
    BuildContext context,
    String url, {
    String title = '支付页面',
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('网页地址无效');
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _openDesktop(url, title);
    }
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InternalBrowserPage(url: url, title: title),
      ),
    );
  }

  static Future<void> _openDesktop(String url, String title) async {
    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        title: title,
        titleBarHeight: 44,
        windowWidth: 1100,
        windowHeight: 760,
      ),
    );
    webview.launch(url);
  }

  @override
  State<InternalBrowserPage> createState() => _InternalBrowserPageState();
}

class _InternalBrowserPageState extends State<InternalBrowserPage> {
  late final WebViewController _controller;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: widget.title,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: '刷新',
          onPressed: _controller.reload,
        ),
      ],
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}
