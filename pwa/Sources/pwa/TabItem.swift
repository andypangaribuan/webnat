import Foundation
import WebKit

class TabItem: NSObject {
    let id: String = UUID().uuidString
    let webView: WKWebView
    var title: String
    var customTitle: String?
    var urlString: String
    var themeMode: String
    var snapshotDataUrl: String = ""

    var displayTitle: String {
        if let custom = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return title
    }

    init(webView: WKWebView, title: String, urlString: String, themeMode: String) {
        self.webView = webView
        self.title = title
        self.urlString = urlString
        self.themeMode = themeMode
        super.init()
    }
}
