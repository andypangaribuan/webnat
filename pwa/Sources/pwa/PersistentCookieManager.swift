import Foundation
import WebKit

class PersistentCookieManager: NSObject, WKHTTPCookieStoreObserver {
    private let cookieStore: WKHTTPCookieStore
    private let defaultsKey: String
    private var isRestoring = false

    init(cookieStore: WKHTTPCookieStore, bundleId: String) {
        self.cookieStore = cookieStore
        self.defaultsKey = "saved_cookies_\(bundleId)"
        super.init()
        self.cookieStore.add(self)
    }

    deinit {
        cookieStore.remove(self)
    }

    func restoreCookies(completion: @escaping () -> Void) {
        guard let savedArray = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: Any]], !savedArray.isEmpty else {
            completion()
            return
        }

        isRestoring = true
        let group = DispatchGroup()

        for dict in savedArray {
            var props = [HTTPCookiePropertyKey: Any]()
            for (k, v) in dict {
                props[HTTPCookiePropertyKey(k)] = v
            }
            if let cookie = HTTPCookie(properties: props) {
                group.enter()
                cookieStore.setCookie(cookie) {
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isRestoring = false
            completion()
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard !isRestoring else { return }
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            var serialized = [[String: Any]]()
            let thirtyDaysFromNow = Date(timeIntervalSinceNow: 30 * 24 * 60 * 60)

            for cookie in cookies {
                guard var props = cookie.properties else { continue }

                // If the website sets a session-only cookie, persist it for 30 days
                if cookie.isSessionOnly || props[.expires] == nil {
                    props[.expires] = thirtyDaysFromNow
                    props.removeValue(forKey: .discard)
                    if let persistentCookie = HTTPCookie(properties: props) {
                        self.isRestoring = true
                        cookieStore.setCookie(persistentCookie) { [weak self] in
                            self?.isRestoring = false
                        }
                    }
                }

                var strDict = [String: Any]()
                for (k, v) in props {
                    if v is String || v is NSNumber || v is Date || v is Data {
                        strDict[k.rawValue] = v
                    } else if let url = v as? URL {
                        strDict[k.rawValue] = url.absoluteString
                    }
                }
                serialized.append(strDict)
            }
            UserDefaults.standard.set(serialized, forKey: self.defaultsKey)
        }
    }
}

