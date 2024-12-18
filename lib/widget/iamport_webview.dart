import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:iamport_flutter/model/iamport_url.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum ActionType { auth, payment }

class IamportWebView extends StatefulWidget {
  static final Color primaryColor = Color(0xff344e81);
  static final String html = '''
    <html>
      <head>
        <meta http-equiv="content-type" content="text/html; charset=utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">

        <script type="text/javascript" src="https://cdn.iamport.kr/v1/iamport.js"></script>
      </head>
      <body></body>
    </html>
  ''';

  final ActionType type;
  final PreferredSizeWidget? appBar;
  final Widget? initialChild;
  final ValueSetter<WebViewController> executeJS;
  final ValueSetter<Map<String, String>> useQueryData;
  final Function isPaymentOver;
  final Function customPGAction;
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;
  final String? customUserAgent;

  IamportWebView({
    required this.type,
    this.appBar,
    this.initialChild,
    required this.executeJS,
    required this.useQueryData,
    required this.isPaymentOver,
    required this.customPGAction,
    required this.gestureRecognizers,
    this.customUserAgent,
  });

  @override
  _IamportWebViewState createState() => _IamportWebViewState();
}

class _IamportWebViewState extends State<IamportWebView> {
  late WebViewController _webViewController;
  StreamSubscription? _sub;
  late int _isWebviewLoaded;
  late int _isImpLoaded;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          // 웹뷰 로딩 완료시에 화면 전환
          if (_isWebviewLoaded == 1) {
            setState(() {
              _isWebviewLoaded = 0;
            });
          }
          // 페이지 로딩 완료시 IMP 코드 실행
          if (_isImpLoaded == 0) {
            widget.executeJS(this._webViewController);
            _isImpLoaded++;
          }
        },
        onNavigationRequest: (request) {
          // print("url: " + request.url);
          if (widget.isPaymentOver(request.url)) {
            String decodedUrl = Uri.decodeComponent(request.url);
            widget.useQueryData(Uri.parse(decodedUrl).queryParameters);

            return NavigationDecision.prevent;
          }

          final iamportUrl = IamportUrl(request.url);
          if (iamportUrl.isAppLink()) {
            // print("appLink: " + iamportUrl.appUrl!);
            // 앱 실행 로직을 iamport_url 모듈로 이동
            iamportUrl.launchApp();
            return NavigationDecision.prevent;
          }

          return NavigationDecision.navigate;
        },
        onPageStarted: (url) {},
      ))
      ..setUserAgent(widget.customUserAgent)
      ..loadHtmlString(IamportWebView.html);

    if (widget.type == ActionType.payment) {
      // 스마일페이, 나이스 실시간 계좌이체
      _sub = widget.customPGAction(this._webViewController);
    }

    _isWebviewLoaded = 0;
    _isImpLoaded = 0;
    if (widget.initialChild != null) {
      _isWebviewLoaded++;
    }
  }

  @override
  void dispose() {
    super.dispose();
    if (_sub != null) _sub!.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.appBar,
      body: SafeArea(
        child: IndexedStack(
          index: _isWebviewLoaded,
          children: [
            WebViewWidget(
              controller: _webViewController,
              gestureRecognizers: widget.gestureRecognizers,
            ),
            if (_isWebviewLoaded == 1) widget.initialChild!,
          ],
        ),
      ),
    );
  }
}
