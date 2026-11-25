import SwiftUI
import WebKit
import SafariServices
import AuthenticationServices

/// 오름잇 웹 주소 · 앱 표시 · 주소 판단 (Foundation 만 쓰므로 어디서나 부를 수 있다)
enum OreumitWeb {
    static let home = URL(string: "https://www.oreumit.com/")!
    /// 웹이 「앱 안」인지 알 수 있게 사용자 에이전트 끝에 붙인다
    static let userAgent = "Mobile/15E148 OreumitApp/1.0"
    static let shareHandler = "oreumitShare"
    static let callbackScheme = "oreumit"
    /// Supabase Auth 의 Redirect URLs 에 이 주소가 있어야 한다
    static let loginCallback = "oreumit://login"
    /// 웹의 navigator.share(없으면 새로 만든다)와 window.OreumitApp.share 가 앱의 공유 시트를 연다
    static let bridgeScript = """
    (function () {
      if (window.OreumitApp) return;
      window.OreumitApp = {
        version: '1.0',
        share: function (data) {
          window.webkit.messageHandlers.oreumitShare.postMessage(JSON.parse(JSON.stringify(data || {})));
          return Promise.resolve();
        }
      };
      if (!navigator.share) navigator.share = function (data) { return window.OreumitApp.share(data); };
    })();
    """

    static func isOwnSite(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "oreumit.com" || host.hasSuffix(".oreumit.com") || host == "jeju-tour-six.vercel.app"
    }

    /// 웹의 소셜 로그인(구글 · 카카오 · 네이버 · LINE)은 Supabase 의 authorize 주소로 간다
    static func isSupabaseLogin(_ url: URL) -> Bool {
        (url.host?.lowercased().hasSuffix(".supabase.co") ?? false) && url.path.hasSuffix("/auth/v1/authorize")
    }

    /// 로그인 시작 주소의 redirect_to 를 앱 주소로 바꾼다. 원래 돌아가려던 주소도 함께 돌려준다
    static func appLogin(_ url: URL) -> (start: URL, original: URL)? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = parts.queryItems ?? []
        let original = items.first(where: { $0.name == "redirect_to" })?.value.flatMap { URL(string: $0) } ?? home
        items.removeAll { $0.name == "redirect_to" }
        items.append(URLQueryItem(name: "redirect_to", value: loginCallback))
        parts.queryItems = items
        guard let start = parts.url else { return nil }
        return (start, original)
    }

    /// 웹이 원래 돌아가려던 주소에 로그인 결과(? 뒤 · # 뒤)를 붙인다
    static func landing(_ original: URL, from callback: URL) -> URL? {
        guard var target = URLComponents(url: original, resolvingAgainstBaseURL: false),
              let back = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { return nil }
        if let extra = back.queryItems, !extra.isEmpty {
            target.queryItems = (target.queryItems ?? []) + extra
        }
        target.percentEncodedFragment = back.percentEncodedFragment
        return target.url
    }
}

/// 앱이 여는 오름잇 웹과 오프라인 상태
final class WebModel: ObservableObject {
    @Published var offline = false
    weak var webView: WKWebView?

    func reload() {
        offline = false
        guard let webView else { return }
        if webView.backForwardList.currentItem == nil {
            webView.load(URLRequest(url: OreumitWeb.home))
        } else {
            webView.reload()
        }
    }
}

struct WebContainer: UIViewRepresentable {
    @ObservedObject var model: WebModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = OreumitWeb.userAgent
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(context.coordinator, name: OreumitWeb.shareHandler)
        config.userContentController.addUserScript(
            WKUserScript(source: OreumitWeb.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        model.webView = webView
        webView.load(URLRequest(url: OreumitWeb.home))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

private extension UIView {
    /// 이 화면 위에 띄울 수 있는 맨 위 화면
    var topController: UIViewController? {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension WebContainer {
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
        ASWebAuthenticationPresentationContextProviding {
        let model: WebModel
        private var login: ASWebAuthenticationSession?

        init(model: WebModel) {
            self.model = model
        }

        // MARK: 이동

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow)
                return
            }
            if OreumitWeb.isSupabaseLogin(url) {
                decisionHandler(.cancel)
                startLogin(url, from: webView)
                return
            }
            if scheme == "http" || scheme == "https" {
                let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
                if mainFrame && !OreumitWeb.isOwnSite(url) {
                    decisionHandler(.cancel)
                    openOutside(url, from: webView)
                } else {
                    decisionHandler(.allow)
                }
                return
            }
            if ["about", "blob", "data", "javascript"].contains(scheme) {
                decisionHandler(.allow)
                return
            }
            // tel: · mailto: · 지도 앱 주소는 iOS 가 연다
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        }

        /// target="_blank" · window.open
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            if OreumitWeb.isSupabaseLogin(url) {
                startLogin(url, from: webView)
            } else if OreumitWeb.isOwnSite(url) {
                webView.load(navigationAction.request)
            } else {
                openOutside(url, from: webView)
            }
            return nil
        }

        /// 다른 사이트는 앱 안 Safari 화면으로, 그 밖의 주소(tel: 등)는 iOS 로 연다
        private func openOutside(_ url: URL, from webView: WKWebView) {
            let scheme = url.scheme?.lowercased()
            if scheme == "http" || scheme == "https", let top = webView.topController {
                top.present(SFSafariViewController(url: url), animated: true)
            } else {
                UIApplication.shared.open(url)
            }
        }

        // MARK: 로그인 — 구글은 앱 안 웹 화면의 로그인을 막으므로 모든 소셜 로그인을 시스템 로그인 창에서 연다

        private func startLogin(_ url: URL, from webView: WKWebView) {
            guard let request = OreumitWeb.appLogin(url) else { return }
            let original = request.original
            let session = ASWebAuthenticationSession(url: request.start, callbackURLScheme: OreumitWeb.callbackScheme) { [weak self, weak webView] callback, _ in
                Task { @MainActor in
                    self?.login = nil
                    guard let webView else { return }
                    if let callback, let target = OreumitWeb.landing(original, from: callback) {
                        webView.load(URLRequest(url: target))
                    } else {
                        webView.reload()  // 취소하면 로그인 화면을 처음 상태로
                    }
                }
            }
            session.presentationContextProvider = self
            self.login = session
            if !session.start() {
                self.login = nil
                webView.reload()
            }
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            model.webView?.window ?? ASPresentationAnchor()
        }

        // MARK: 공유

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == OreumitWeb.shareHandler, let webView = model.webView else { return }
            let data = message.body as? [String: Any] ?? [:]
            var items: [Any] = []
            if let text = (data["text"] as? String) ?? (data["title"] as? String), !text.isEmpty {
                items.append(text)
            }
            if let link = (data["url"] as? String).flatMap({ URL(string: $0) }) ?? webView.url {
                items.append(link)
            }
            guard !items.isEmpty, let top = webView.topController else { return }
            let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = webView
            top.present(sheet, animated: true)
        }

        // MARK: 웹의 alert · confirm (WKWebView 는 앱이 그리지 않으면 아무것도 보이지 않는다)

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let top = webView.topController else {
                completionHandler()
                return
            }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler() })
            top.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let top = webView.topController else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completionHandler(true) })
            top.present(alert, animated: true)
        }

        // MARK: 오프라인

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.offline = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showOfflineIfNeeded(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showOfflineIfNeeded(error)
        }

        private func showOfflineIfNeeded(_ error: Error) {
            let failure = error as NSError
            let network = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                           NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed]
            if failure.domain == NSURLErrorDomain && network.contains(failure.code) {
                model.offline = true
            }
        }
    }
}
