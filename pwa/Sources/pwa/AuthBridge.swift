import Foundation
import WebKit

class AuthBridge: NSObject, WKScriptMessageHandler {
    private let bundleId: String
    private let fallbackKey: String
    weak var appDelegate: AppDelegate?

    init(bundleId: String) {
        self.bundleId = bundleId
        self.fallbackKey = "saved_pwd_\(bundleId)"
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }

        if action == "savePassword", let pwd = body["password"] as? String, !pwd.isEmpty {
            KeychainHelper.save(password: pwd, service: bundleId)
            UserDefaults.standard.set(pwd, forKey: fallbackKey)
        } else if action == "requestPassword" {
            let saved = KeychainHelper.load(service: bundleId) ?? UserDefaults.standard.string(forKey: fallbackKey)
            if let pwd = saved, !pwd.isEmpty {
                let jsData = try? JSONSerialization.data(withJSONObject: [pwd], options: [])
                let jsStr = String(data: jsData ?? Data(), encoding: .utf8) ?? "[\"\"]"
                let script = """
                (() => {
                    const pwd = (\(jsStr))[0];
                    const pwdInput = document.querySelector('input[type="password"]');
                    if (pwdInput && !pwdInput.value) {
                        pwdInput.focus();
                        pwdInput.value = pwd;
                        pwdInput.dispatchEvent(new Event('input', { bubbles: true }));
                        pwdInput.dispatchEvent(new Event('change', { bubbles: true }));
                        setTimeout(() => {
                            const btn = document.querySelector('button[type="submit"]') || pwdInput.closest('form')?.querySelector('button') || pwdInput.closest('div')?.parentElement?.querySelector('button');
                            if (btn && !btn.disabled) {
                                btn.click();
                            }
                        }, 120);
                    }
                })();
                """
                DispatchQueue.main.async { [weak self] in
                    message.webView?.evaluateJavaScript(script, completionHandler: nil)
                    _ = self
                }
            }
        }
    }
}

