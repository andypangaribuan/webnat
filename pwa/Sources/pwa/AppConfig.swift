import Foundation

struct AppConfig {
    let targetUrlString: String
    let appTitle: String
    let themeMode: String
    let bundleId: String

    static let shared: AppConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        let env = ProcessInfo.processInfo.environment

        let rawUrl = (info["PWATargetURL"] as? String)
            ?? env["PWA_TARGET_URL"]
            ?? ""
        let url = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)

        let title = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? env["PWA_APP_NAME"]
            ?? "PWA"

        let theme = ((info["PWAThemeMode"] as? String)
            ?? env["PWA_THEME_MODE"]
            ?? "system").lowercased()

        let bundleId = Bundle.main.bundleIdentifier
            ?? (info["CFBundleIdentifier"] as? String)
            ?? "io.bulannov.pwa"

        return AppConfig(
            targetUrlString: url,
            appTitle: title,
            themeMode: theme,
            bundleId: bundleId
        )
    }()
}

