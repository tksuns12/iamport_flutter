import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:iamport_flutter/model/iamport_validation.dart';
import 'package:iamport_flutter/model/payment_data.dart';
import 'package:iamport_flutter/model/url_data.dart';
import 'package:iamport_flutter/widget/iamport_error.dart';
import 'package:iamport_flutter/widget/iamport_webview.dart';
import 'package:app_links/app_links.dart';
import 'package:webview_flutter/webview_flutter.dart';

class IamportPayment extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? initialChild;
  final String userCode;
  final PaymentData data;
  final callback;
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;
  final _appLinks = AppLinks();

  IamportPayment({
    Key? key,
    this.appBar,
    this.initialChild,
    required this.userCode,
    required this.data,
    required this.callback,
    this.gestureRecognizers,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    IamportValidation validation =
        IamportValidation(this.userCode, this.data, this.callback);

    if (validation.getIsValid()) {
      var redirectUrl = UrlData.redirectUrl;
      if (this.data.mRedirectUrl != null &&
          this.data.mRedirectUrl!.isNotEmpty) {
        redirectUrl = this.data.mRedirectUrl!;
      }

      return IamportWebView(
        type: ActionType.payment,
        appBar: this.appBar,
        initialChild: this.initialChild,
        gestureRecognizers: this.gestureRecognizers ?? {},
        executeJS: (WebViewController controller) {
          controller.runJavaScript('''
            IMP.init("${this.userCode}");
            IMP.request_pay(${jsonEncode(this.data.toJson())}, function(response) {
              const query = [];
              Object.keys(response).forEach(function(key) {
                query.push(key + "=" + response[key]);
              });
              location.href = "$redirectUrl" + "?" + query.join("&");
            });
          ''');
        },
        customPGAction: (WebViewController controller) {
          /* [v0.9.6] niceMobileV2: true 대비 코드 작성 */
          if (this.data.pg == 'nice' && this.data.payMethod == 'trans') {
            try {
              StreamSubscription sub =
                  _appLinks.uriLinkStream.listen((Uri? link) async {
                if (link != null) {
                  String decodedUrl = Uri.decodeComponent(link.toString());
                  Uri parsedUrl = Uri.parse(decodedUrl);
                  String scheme = parsedUrl.scheme;
                  if (scheme == data.appScheme.toLowerCase()) {
                    String queryToString = parsedUrl.query;
                    String? niceTransRedirectionUrl;
                    parsedUrl.queryParameters.forEach((key, value) {
                      if (key == 'callbackparam1') {
                        niceTransRedirectionUrl = value;
                      }
                    });
                    await controller.runJavaScript('''
                    location.href = "$niceTransRedirectionUrl?$queryToString";
                  ''');
                  }
                }
              });
              return sub;
            } on FormatException {}
          }
          return null;
        },
        useQueryData: (Map<String, String> data) {
          this.callback(data);
        },
        isPaymentOver: (String url) {
          if (url.startsWith(redirectUrl)) {
            return true;
          }

          if (this.data.payMethod == 'trans') {
            /* [IOS] imp_uid와 merchant_uid값만 전달되기 때문에 결제 성공 또는 실패 구분할 수 없음 */
            String decodedUrl = Uri.decodeComponent(url);
            Uri parsedUrl = Uri.parse(decodedUrl);
            String scheme = parsedUrl.scheme;
            if (this.data.pg == 'html5_inicis') {
              Map<String, String> query = parsedUrl.queryParameters;
              if (query['m_redirect_url'] != null &&
                  scheme == this.data.appScheme.toLowerCase()) {
                if (query['m_redirect_url']!.contains(redirectUrl)) {
                  return true;
                }
              }
            }
          }

          return false;
        },
      );
    } else {
      return IamportError(ActionType.payment, validation.getErrorMessage());
    }
  }
}
