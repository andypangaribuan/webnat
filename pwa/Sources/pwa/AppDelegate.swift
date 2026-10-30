import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
    var window: NSWindow!
    var tabContainerView: NSView!
    var overviewWebView: WKWebView!
    var isTabOverviewVisible = false
    var isTrafficLightsHidden = true

    var tabs: [TabItem] = []
    var activeTabId: String?

    var cookieManager: PersistentCookieManager?
    var authBridge: AuthBridge?
    var overviewBridge: TabOverviewBridge?
    var bookmarkManager: BookmarkManager?

    let config = AppConfig.shared
    var targetUrlString: String { config.targetUrlString }
    var appTitle: String { config.appTitle }
    var themeMode: String { config.themeMode }
    var bundleId: String { config.bundleId }

    var activeTab: TabItem? {
        if let id = activeTabId, let found = tabs.first(where: { $0.id == id }) {
            return found
        }
        return tabs.first
    }

    var activeWebView: WKWebView? {
        return activeTab?.webView
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupKeyboardMonitor()

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(x: screen.midX - 640, y: screen.midY - 400, width: 1280, height: 800)

        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        repositionTrafficLights()

        // Configure Dark / Light / System appearance
        if themeMode == "dark" {
            let darkAppearance = NSAppearance(named: .darkAqua)
            NSApp.appearance = darkAppearance
            window.appearance = darkAppearance
            window.backgroundColor = NSColor(srgbRed: 20/255.0, green: 20/255.0, blue: 22/255.0, alpha: 1.0)
        } else if themeMode == "light" {
            let lightAppearance = NSAppearance(named: .aqua)
            NSApp.appearance = lightAppearance
            window.appearance = lightAppearance
            window.backgroundColor = NSColor(srgbRed: 245/255.0, green: 245/255.0, blue: 245/255.0, alpha: 1.0)
        } else {
            NSApp.appearance = nil
            window.appearance = nil
            window.backgroundColor = NSColor.windowBackgroundColor
        }

        window.setFrameAutosaveName("MainWindow_\(bundleId)")

        authBridge = AuthBridge(bundleId: bundleId)
        authBridge?.appDelegate = self
        bookmarkManager = BookmarkManager(bundleId: bundleId)

        let rootBounds = window.contentView!.bounds
        tabContainerView = NSView(frame: rootBounds)
        tabContainerView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(tabContainerView)

        setupTabOverviewWebView(frame: rootBounds)

        // Setup persistent cookie management and restore cookies before creating initial tab
        cookieManager = PersistentCookieManager(cookieStore: WKWebsiteDataStore.default().httpCookieStore, bundleId: bundleId)
        cookieManager?.restoreCookies { [weak self] in
            guard let self = self else { return }
            if !self.targetUrlString.isEmpty {
                self.createNewTabAndLoadHome()
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        repositionTrafficLights()
    }

    // Monitor global app shortcuts:
    // - Cmd + Control + . -> Toggle Safari-style Tab Overview
    // - Cmd + Control + / -> Toggle Window Traffic Light Buttons (Close, Minimize, Maximize)
    // - Cmd + Control + N -> Open New Tab with URL Input
    // - Cmd + Control + , -> Toggle Theme (Dark / Light) on Active Tab
    // - Cmd + Control + Y -> Rename Active Tab (shown in Show Tab Overview)
    // - Escape            -> Dismiss Tab Overview
    // - Ctrl + Tab        -> Cycle Tabs
    func setupKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers?.lowercased()

            // Cmd + Control + . -> Toggle Safari-style Tab Overview
            if flags == [.command, .control] && (chars == "." || event.keyCode == 47) {
                self.toggleTabOverview()
                return nil
            }

            // Cmd + Control + / -> Toggle 3 Window Traffic Light Buttons (Hide / Show)
            if flags == [.command, .control] && (chars == "/" || event.keyCode == 44) {
                self.toggleTrafficLights()
                return nil
            }

            // Cmd + Control + N -> New Tab with URL Prompt
            if flags == [.command, .control] && (chars == "n" || event.keyCode == 45) {
                self.promptNewTabWithURL()
                return nil
            }

            // Cmd + Control + , -> Change/Toggle Theme on Active Tab
            if flags == [.command, .control] && (chars == "," || event.keyCode == 43) {
                self.toggleActiveTabTheme()
                return nil
            }

            // Cmd + Control + Y -> Rename Active Tab
            if flags == [.command, .control] && (chars == "y" || event.keyCode == 16) {
                self.promptRenameActiveTab()
                return nil
            }

            // Cmd + Control + B -> Save Current Page into Bookmarks
            if flags == [.command, .control] && (chars == "b" || event.keyCode == 11) {
                self.promptSaveBookmark()
                return nil
            }

            // Escape closes Tab Overview when visible
            if self.isTabOverviewVisible && event.keyCode == 53 {
                self.hideTabOverview()
                return nil
            }

            // Cmd + Option + Tab / Cmd + Option + Shift + Tab -> Cycle Tabs
            if flags == [.command, .option] && event.keyCode == 48 {
                self.selectNextTab()
                return nil
            }
            if flags == [.command, .option, .shift] && event.keyCode == 48 {
                self.selectPreviousTab()
                return nil
            }

            return event
        }
    }

    // ========================================================================
    // Multi-Tab Creation, Selection & Management
    // ========================================================================
    func makeUserScript(initialTheme: String? = nil) -> WKUserScript {
        let lightsHiddenLiteral = isTrafficLightsHidden ? "true" : "false"
        let effectiveTheme = initialTheme ?? themeMode
        let scriptSource = """
        let forcedTheme = '\(effectiveTheme)';
        const syncThemeStorage = (themeVal) => {
            if (themeVal === 'dark' || themeVal === 'light') {
                try {
                    localStorage.setItem('dbx-theme', themeVal);
                    localStorage.setItem('theme', themeVal);
                    localStorage.setItem('color-theme', themeVal);
                    localStorage.setItem('vitepress-theme-appearance', themeVal);
                } catch (e) {}
            }
        };
        syncThemeStorage(forcedTheme);

        if (\(lightsHiddenLiteral)) {
            document.documentElement.classList.add('dbx-macos-lights-hidden');
        }

        const getEffectiveBgLuminance = () => {
            const parseRgb = (str) => {
                if (!str) return null;
                const m = str.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([\\d.]+))?\\)/);
                if (!m) return null;
                const a = m[4] !== undefined ? parseFloat(m[4]) : 1;
                if (a < 0.1) return null;
                return [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)];
            };
            const candidates = [
                document.body,
                document.querySelector('#root'),
                document.querySelector('#app'),
                document.querySelector('main'),
                document.documentElement
            ].filter(Boolean);
            for (const el of candidates) {
                if (el === document.documentElement && el.classList.contains('agy-auto-dark')) continue;
                const rgb = parseRgb(window.getComputedStyle(el).backgroundColor);
                if (rgb) {
                    return (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255;
                }
            }
            return 1.0;
        };

        const applyTrafficLightStyles = () => {
            const styleId = 'dbx-macos-traffic-lights-style';
            if (!document.getElementById(styleId)) {
                const style = document.createElement('style');
                style.id = styleId;
                style.textContent = `
                    *, html, body {
                        scrollbar-width: none !important;
                        -ms-overflow-style: none !important;
                    }
                    *::-webkit-scrollbar,
                    html::-webkit-scrollbar,
                    body::-webkit-scrollbar {
                        display: none !important;
                        width: 0px !important;
                        height: 0px !important;
                        background: transparent !important;
                    }
                    html:not(.dbx-macos-fullscreen):not(.dbx-macos-lights-hidden) .app-toolbar {
                        margin-left: 0px !important;
                        padding-left: 78px !important;
                    }
                    html.dbx-macos-fullscreen .app-toolbar,
                    html.dbx-macos-lights-hidden .app-toolbar {
                        margin-left: 0px !important;
                        padding-left: 12px !important;
                    }
                    html.agy-auto-dark {
                        background-color: #ffffff !important;
                        filter: invert(0.92) hue-rotate(180deg) !important;
                        min-height: 100vh;
                    }
                    html.agy-auto-dark img,
                    html.agy-auto-dark video,
                    html.agy-auto-dark picture,
                    html.agy-auto-dark canvas,
                    html.agy-auto-dark iframe,
                    html.agy-auto-dark [style*="background-image"] {
                        filter: invert(1) hue-rotate(180deg) !important;
                    }
                `;
                (document.head || document.documentElement).appendChild(style);
            }

            if (forcedTheme === 'dark' || forcedTheme === 'light') {
                const root = document.documentElement;
                if (root) {
                    root.classList.toggle('dark', forcedTheme === 'dark');
                    root.classList.toggle('light', forcedTheme === 'light');
                    root.dataset.theme = forcedTheme;
                    root.style.colorScheme = forcedTheme;

                    if (document.body) {
                        if (forcedTheme === 'dark') {
                            const lum = getEffectiveBgLuminance();
                            root.classList.toggle('agy-auto-dark', lum > 0.55);
                        } else {
                            root.classList.remove('agy-auto-dark');
                        }
                    }
                }
            }

            const isCompact = document.documentElement.classList.contains('dbx-macos-fullscreen') ||
                              document.documentElement.classList.contains('dbx-macos-lights-hidden');
            const targetPadding = isCompact ? '12px' : '78px';

            if (!document.body) return;
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            let node;
            while ((node = walker.nextNode())) {
                const val = node.nodeValue.trim();
                if (val === 'DBX' || val.toLowerCase().includes('database')) {
                    let el = node.parentElement;
                    while (el && el !== document.body) {
                        if (el.style && el.style.marginLeft && el.style.marginLeft !== '0px') {
                            el.style.marginLeft = '0px';
                        }
                        const r = el.getBoundingClientRect();
                        if (r.top < 15 && r.left < 5 && r.width > 250 && r.height >= 24 && r.height <= 60) {
                            el.style.setProperty('margin-left', '0px', 'important');
                            el.style.setProperty('padding-left', targetPadding, 'important');
                            break;
                        }
                        el = el.parentElement;
                    }
                    break;
                }
            }
        };
        window.applyTrafficLightStyles = applyTrafficLightStyles;
        window.setForcedTheme = (newTheme) => {
            forcedTheme = newTheme;
            syncThemeStorage(forcedTheme);
            applyTrafficLightStyles();
        };

        let hasAskedPassword = false;
        const checkLoginForm = () => {
            const pwdInput = document.querySelector('input[type="password"]');
            if (pwdInput && !pwdInput.value && !hasAskedPassword) {
                hasAskedPassword = true;
                window.webkit.messageHandlers.auth?.postMessage({ action: 'requestPassword' });
            }
        };

        document.addEventListener('input', (e) => {
            if (e.target && e.target.type === 'password' && e.target.value) {
                window.webkit.messageHandlers.auth?.postMessage({ action: 'savePassword', password: e.target.value });
            }
        }, true);

        document.addEventListener('submit', (e) => {
            const pwdInput = document.querySelector('input[type="password"]');
            if (pwdInput && pwdInput.value) {
                window.webkit.messageHandlers.auth?.postMessage({ action: 'savePassword', password: pwdInput.value });
            }
        }, true);

        const obs = new MutationObserver(() => {
            applyTrafficLightStyles();
            checkLoginForm();
        });

        window.addEventListener('DOMContentLoaded', () => {
            applyTrafficLightStyles();
            checkLoginForm();
            obs.observe(document.body, { childList: true, subtree: true });
        });
        applyTrafficLightStyles();
        checkLoginForm();
        setInterval(applyTrafficLightStyles, 1000);
        """
        return WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    func createConfiguredWebView(using existingConfig: WKWebViewConfiguration? = nil) -> WKWebView {
        let webConfig: WKWebViewConfiguration
        if let existing = existingConfig {
            webConfig = existing
            if webConfig.userContentController.userScripts.isEmpty {
                webConfig.userContentController.addUserScript(makeUserScript())
                if let auth = authBridge {
                    webConfig.userContentController.add(auth, name: "auth")
                }
            }
        } else {
            webConfig = WKWebViewConfiguration()
            let contentController = WKUserContentController()
            contentController.addUserScript(makeUserScript())
            if let auth = authBridge {
                contentController.add(auth, name: "auth")
            }
            webConfig.userContentController = contentController
        }
        webConfig.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"

        let wv = WKWebView(frame: tabContainerView.bounds, configuration: webConfig)
        wv.autoresizingMask = [.width, .height]
        wv.uiDelegate = self
        wv.navigationDelegate = self
        if #available(macOS 13.3, *) {
            wv.isInspectable = true
        }
        return wv
    }

    @discardableResult
    func createNewTab(with existingConfig: WKWebViewConfiguration? = nil, initialUrl: String? = nil, switchTo: Bool = true) -> TabItem {
        if let current = activeTab {
            captureSnapshot(for: current)
        }

        let wv = createConfiguredWebView(using: existingConfig)
        let tab = TabItem(webView: wv, title: appTitle, urlString: initialUrl ?? targetUrlString, themeMode: themeMode)
        applyAppearance(to: tab)
        tabs.append(tab)

        wv.isHidden = true
        tabContainerView.addSubview(wv)

        if let urlStr = initialUrl, let url = URL(string: urlStr) {
            wv.load(URLRequest(url: url))
        }

        if switchTo {
            selectTab(byId: tab.id)
        }
        return tab
    }

    @objc func createNewTabAndLoadHome() {
        if targetUrlString.isEmpty {
            promptNewTabWithURL()
        } else {
            createNewTab(with: nil, initialUrl: targetUrlString, switchTo: true)
        }
    }

    // Cmd + Control + N -> Prompt user to enter a URL and open it in a new tab
    @objc func promptNewTabWithURL() {
        let alert = NSAlert()
        alert.messageText = "Open New Tab"
        alert.informativeText = "Enter the website URL for the new tab:"
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        input.placeholderString = "https://example.com"
        input.stringValue = ""
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            var raw = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return }
            if !raw.lowercased().hasPrefix("http://") && !raw.lowercased().hasPrefix("https://") {
                raw = "https://" + raw
            }
            if self.isTabOverviewVisible {
                self.hideTabOverview()
            }
            self.createNewTab(with: nil, initialUrl: raw, switchTo: true)
        }
    }

    // Cmd + Control + , -> Toggle Dark / Light theme on the active tab
    @objc func toggleActiveTabTheme() {
        guard let tab = activeTab else { return }
        let currentlyDark: Bool
        if tab.themeMode == "dark" {
            currentlyDark = true
        } else if tab.themeMode == "light" {
            currentlyDark = false
        } else {
            currentlyDark = (tab.webView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        }
        tab.themeMode = currentlyDark ? "light" : "dark"
        applyTheme(to: tab)
    }

    func applyAppearance(to tab: TabItem) {
        if tab.themeMode == "dark" {
            tab.webView.appearance = NSAppearance(named: .darkAqua)
        } else if tab.themeMode == "light" {
            tab.webView.appearance = NSAppearance(named: .aqua)
        } else {
            tab.webView.appearance = nil
        }
    }

    func applyTheme(to tab: TabItem) {
        applyAppearance(to: tab)
        let js = "window.setForcedTheme && window.setForcedTheme('\(tab.themeMode)');"
        tab.webView.evaluateJavaScript(js) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard let self = self else { return }
                self.captureSnapshot(for: tab) {
                    if self.isTabOverviewVisible {
                        self.renderTabOverview()
                    }
                }
            }
        }
    }

    // Cmd + Control + Y -> Rename the active tab (displayed in Show Tab Overview)
    @objc func promptRenameActiveTab() {
        guard let tab = activeTab else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "Enter a custom name for this tab (leave blank to reset to page title):"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = tab.title
        input.stringValue = tab.displayTitle
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            tab.customTitle = trimmed.isEmpty ? nil : trimmed
            if self.isTabOverviewVisible {
                self.renderTabOverview()
            }
        }
    }

    // Cmd + Control + B -> Save current page (title & URL) into Bookmarks
    @objc func promptSaveBookmark() {
        let currentTitle: String
        let currentUrl: String
        if let tab = activeTab {
            if let liveTitle = tab.webView.title, !liveTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tab.title = liveTitle
            }
            if let liveUrl = tab.webView.url?.absoluteString, !liveUrl.isEmpty {
                tab.urlString = liveUrl
            }
            currentTitle = tab.displayTitle
            currentUrl = tab.urlString
        } else {
            currentTitle = ""
            currentUrl = ""
        }

        let alert = NSAlert()
        alert.messageText = "Save Bookmark"
        alert.informativeText = "Save this page to your bookmarks:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 58))

        let titleField = NSTextField(frame: NSRect(x: 0, y: 32, width: 340, height: 24))
        titleField.placeholderString = "Bookmark Name"
        titleField.stringValue = currentTitle

        let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        urlField.placeholderString = "https://example.com"
        urlField.stringValue = currentUrl

        container.addSubview(titleField)
        container.addSubview(urlField)
        alert.accessoryView = container
        alert.window.initialFirstResponder = titleField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            var rawUrl = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawUrl.isEmpty else { return }
            if !rawUrl.lowercased().hasPrefix("http://") && !rawUrl.lowercased().hasPrefix("https://") {
                rawUrl = "https://" + rawUrl
            }
            let rawTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self.bookmarkManager?.addBookmark(title: rawTitle.isEmpty ? rawUrl : rawTitle, url: rawUrl)
            if self.isTabOverviewVisible {
                self.renderTabOverview()
            }
        }
    }

    func deleteBookmark(byId id: String) {
        bookmarkManager?.removeBookmark(id: id)
        if isTabOverviewVisible {
            renderTabOverview()
        }
    }

    func reorderBookmarks(orderedIds: [String]) {
        bookmarkManager?.reorderBookmarks(orderedIds: orderedIds)
    }

    func selectTab(byId id: String) {
        guard let target = tabs.first(where: { $0.id == id }) else { return }
        if let current = activeTab, current.id != target.id {
            captureSnapshot(for: current)
        }
        activeTabId = target.id
        for tab in tabs {
            let isSelected = (tab.id == target.id)
            tab.webView.isHidden = !isSelected
            if isSelected {
                tab.webView.frame = tabContainerView.bounds
                window.makeFirstResponder(tab.webView)
            }
        }
        repositionTrafficLights()
    }

    @objc func selectNextTab() {
        guard tabs.count > 1, let currentId = activeTabId, let idx = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let nextIdx = (idx + 1) % tabs.count
        selectTab(byId: tabs[nextIdx].id)
    }

    @objc func selectPreviousTab() {
        guard tabs.count > 1, let currentId = activeTabId, let idx = tabs.firstIndex(where: { $0.id == currentId }) else { return }
        let prevIdx = (idx - 1 + tabs.count) % tabs.count
        selectTab(byId: tabs[prevIdx].id)
    }

    func closeTab(byId id: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs.count <= 1 {
            if targetUrlString.isEmpty {
                let removed = tabs.remove(at: idx)
                removed.webView.stopLoading()
                removed.webView.removeFromSuperview()
                activeTabId = nil
                if isTabOverviewVisible {
                    renderTabOverview()
                }
            } else if isTabOverviewVisible {
                hideTabOverview()
            } else {
                window.performClose(nil)
            }
            return
        }

        let removed = tabs.remove(at: idx)
        removed.webView.stopLoading()
        removed.webView.removeFromSuperview()

        if activeTabId == id {
            let newIdx = min(idx, tabs.count - 1)
            selectTab(byId: tabs[newIdx].id)
        }

        if isTabOverviewVisible {
            renderTabOverview()
        }
    }

    @objc func closeCurrentTabOrWindow() {
        if isTabOverviewVisible {
            hideTabOverview()
            return
        }
        if let currentId = activeTabId, (tabs.count > 1 || targetUrlString.isEmpty) {
            closeTab(byId: currentId)
        } else {
            window.performClose(nil)
        }
    }

    func captureSnapshot(for tab: TabItem, completion: (() -> Void)? = nil) {
        if let t = tab.webView.title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tab.title = t
        } else if let host = tab.webView.url?.host {
            tab.title = host
        }
        if let u = tab.webView.url?.absoluteString, !u.isEmpty {
            tab.urlString = u
        }

        let snapConfig = WKSnapshotConfiguration()
        snapConfig.snapshotWidth = 640
        tab.webView.takeSnapshot(with: snapConfig) { image, _ in
            if let image = image,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                tab.snapshotDataUrl = "data:image/png;base64," + png.base64EncodedString()
            }
            completion?()
        }
    }

    // ========================================================================
    // Safari-Style Tab Overview Grid (Cmd + Control + .)
    // ========================================================================
    func setupTabOverviewWebView(frame: NSRect) {
        let webConfig = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let bridge = TabOverviewBridge()
        bridge.appDelegate = self
        self.overviewBridge = bridge
        controller.add(bridge, name: "tabOverview")
        webConfig.userContentController = controller

        overviewWebView = WKWebView(frame: frame, configuration: webConfig)
        overviewWebView.autoresizingMask = [.width, .height]
        overviewWebView.setValue(false, forKey: "drawsBackground")
        overviewWebView.isHidden = true
        window.contentView?.addSubview(overviewWebView)
        overviewWebView.loadHTMLString(TabOverviewBridge.overviewHTML, baseURL: nil)
    }

    @objc func toggleTabOverview() {
        if isTabOverviewVisible {
            hideTabOverview()
        } else {
            showTabOverview()
        }
    }

    func showTabOverview() {
        let presentOverview = { [weak self] in
            guard let self = self else { return }
            self.isTabOverviewVisible = true
            self.overviewWebView.frame = self.window.contentView!.bounds
            self.overviewWebView.isHidden = false
            self.renderTabOverview()
            self.repositionTrafficLights()
        }
        if let current = activeTab {
            captureSnapshot(for: current) {
                presentOverview()
            }
        } else {
            presentOverview()
        }
    }

    func hideTabOverview() {
        guard isTabOverviewVisible else { return }
        isTabOverviewVisible = false
        overviewWebView.isHidden = true
        if let active = activeWebView {
            window.makeFirstResponder(active)
        }
        repositionTrafficLights()
    }

    func renderTabOverview() {
        for t in tabs {
            if let title = t.webView.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                t.title = title
            } else if let host = t.webView.url?.host {
                t.title = host
            }
            if let url = t.webView.url?.absoluteString, !url.isEmpty {
                t.urlString = url
            }
        }
        let payload: [[String: String]] = tabs.map { t in
            [
                "id": t.id,
                "title": t.displayTitle,
                "url": t.urlString,
                "snapshot": t.snapshotDataUrl
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        let bookmarksPayload = bookmarkManager?.toPayload() ?? []
        let bookmarksData = (try? JSONSerialization.data(withJSONObject: bookmarksPayload, options: [])) ?? Data("[]".utf8)
        let bookmarksJsonStr = String(data: bookmarksData, encoding: .utf8) ?? "[]"
        let activeIdStr = activeTabId ?? ""
        overviewWebView.evaluateJavaScript("window.updateTabs && window.updateTabs(\(jsonStr), '\(activeIdStr)', \(bookmarksJsonStr));", completionHandler: nil)
    }

    // ========================================================================
    // Window Traffic Light Buttons (Toggle Hide/Show via Cmd + Control + /)
    // ========================================================================
    @objc func toggleTrafficLights() {
        isTrafficLightsHidden.toggle()
        repositionTrafficLights()
        syncTrafficLightPaddingInTabs()
    }

    func syncTrafficLightPaddingInTabs() {
        let jsAction = isTrafficLightsHidden
            ? "document.documentElement.classList.add('dbx-macos-lights-hidden'); window.applyTrafficLightStyles && window.applyTrafficLightStyles();"
            : "document.documentElement.classList.remove('dbx-macos-lights-hidden'); window.applyTrafficLightStyles && window.applyTrafficLightStyles();"
        for tab in tabs {
            tab.webView.evaluateJavaScript(jsAction, completionHandler: nil)
        }
    }

    func repositionTrafficLights() {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (i, type) in types.enumerated() {
            if let button = window.standardWindowButton(type) {
                button.isHidden = isTrafficLightsHidden
                if !isTrafficLightsHidden {
                    var frame = button.frame
                    frame.origin.x = CGFloat(14 + (i * 20))
                    frame.origin.y = (button.superview?.frame.height ?? 28) - frame.height - 10
                    button.frame = frame
                }
            }
        }
    }

    // Reopen window when clicking the Dock icon
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
            repositionTrafficLights()
        }
        return true
    }

    func windowDidResize(_ notification: Notification) {
        repositionTrafficLights()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        for tab in tabs {
            tab.webView.evaluateJavaScript("document.documentElement.classList.add('dbx-macos-fullscreen'); window.applyTrafficLightStyles && window.applyTrafficLightStyles();", completionHandler: nil)
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        for tab in tabs {
            tab.webView.evaluateJavaScript("document.documentElement.classList.remove('dbx-macos-fullscreen'); window.applyTrafficLightStyles && window.applyTrafficLightStyles();", completionHandler: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.repositionTrafficLights()
        }
    }

    // ========================================================================
    // WKUIDelegate: File Uploads, JS Dialogs & Opening New Tabs (target="_blank")
    // ========================================================================
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = appTitle
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in
            completionHandler()
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = appTitle
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = appTitle
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    // Intercept target="_blank" and window.open() -> Open as a new in-app Tab!
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let urlStr = navigationAction.request.url?.absoluteString
        let newTab = createNewTab(with: configuration, initialUrl: nil, switchTo: true)
        if let u = urlStr, !u.isEmpty {
            newTab.urlString = u
        }
        return newTab.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let tab = tabs.first(where: { $0.webView === webView }) {
            closeTab(byId: tab.id)
        }
    }

    // ========================================================================
    // WKNavigationDelegate & WKDownloadDelegate
    // ========================================================================
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncTrafficLightPaddingInTabs()
        if let tab = tabs.first(where: { $0.webView === webView }) {
            applyAppearance(to: tab)
            webView.evaluateJavaScript("window.setForcedTheme && window.setForcedTheme('\(tab.themeMode)');", completionHandler: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncTrafficLightPaddingInTabs()
        if let tab = tabs.first(where: { $0.webView === webView }) {
            applyAppearance(to: tab)
            webView.evaluateJavaScript("window.setForcedTheme && window.setForcedTheme('\(tab.themeMode)');", completionHandler: nil)
            captureSnapshot(for: tab) { [weak self] in
                guard let self = self else { return }
                if self.isTabOverviewVisible {
                    self.renderTabOverview()
                }
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }
        if let url = navigationAction.request.url {
            if let scheme = url.scheme?.lowercased(), scheme != "http" && scheme != "https" && scheme != "blob" && scheme != "data" && scheme != "about" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel, preferences)
                return
            }
            // Cmd + Click on a normal link opens it in a new in-app Tab
            if navigationAction.navigationType == .linkActivated && navigationAction.modifierFlags.contains(.command) {
                createNewTab(with: nil, initialUrl: url.absoluteString, switchTo: true)
                decisionHandler(.cancel, preferences)
                return
            }
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().contains("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = suggestedFilename
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloadsURL
        }
        savePanel.beginSheetModal(for: window) { result in
            if result == .OK, let url = savePanel.url {
                try? FileManager.default.removeItem(at: url)
                completionHandler(url)
            } else {
                completionHandler(nil)
            }
        }
    }

    // ========================================================================
    // Complete macOS Application Menu
    // ========================================================================
    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: appTitle)
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appTitle)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide \(appTitle)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(appTitle)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File Menu (New Tab, New Tab with URL, Rename Tab, Close Tab)
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New Tab", action: #selector(createNewTabAndLoadHome), keyEquivalent: "t")
        let newTabUrlItem = fileMenu.addItem(withTitle: "New Tab with URL…", action: #selector(promptNewTabWithURL), keyEquivalent: "n")
        newTabUrlItem.keyEquivalentModifierMask = [.command, .control]
        let renameTabItem = fileMenu.addItem(withTitle: "Rename Tab…", action: #selector(promptRenameActiveTab), keyEquivalent: "y")
        renameTabItem.keyEquivalentModifierMask = [.command, .control]
        let saveBookmarkItem = fileMenu.addItem(withTitle: "Save Bookmark…", action: #selector(promptSaveBookmark), keyEquivalent: "b")
        saveBookmarkItem.keyEquivalentModifierMask = [.command, .control]
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeCurrentTabOrWindow), keyEquivalent: "w")

        // Edit Menu (Enables Cmd+Z, Cmd+Shift+Z, Cmd+X, Cmd+C, Cmd+V, Cmd+A)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View Menu (Tab Overview Cmd+Control+., Window Buttons Cmd+Control+/, Theme Cmd+Control+,, Zooming, Reload)
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let tabOverviewItem = viewMenu.addItem(withTitle: "Show Tab Overview", action: #selector(toggleTabOverview), keyEquivalent: ".")
        tabOverviewItem.keyEquivalentModifierMask = [.command, .control]

        let toggleButtonsItem = viewMenu.addItem(withTitle: "Toggle Window Buttons", action: #selector(toggleTrafficLights), keyEquivalent: "/")
        toggleButtonsItem.keyEquivalentModifierMask = [.command, .control]

        let toggleThemeItem = viewMenu.addItem(withTitle: "Toggle Active Tab Theme", action: #selector(toggleActiveTabTheme), keyEquivalent: ",")
        toggleThemeItem.keyEquivalentModifierMask = [.command, .control]

        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Reload Page", action: #selector(reloadPage), keyEquivalent: "r")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(resetZoom), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+")
        let zoomInEqual = viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn), keyEquivalent: "=")
        zoomInEqual.isAlternate = true
        zoomInEqual.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-")
        viewMenu.addItem(NSMenuItem.separator())
        let fullScreenItem = viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]

        // Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        let nextTabItem = windowMenu.addItem(withTitle: "Show Next Tab", action: #selector(selectNextTab), keyEquivalent: "\t")
        nextTabItem.keyEquivalentModifierMask = [.command, .option]
        let prevTabItem = windowMenu.addItem(withTitle: "Show Previous Tab", action: #selector(selectPreviousTab), keyEquivalent: "\t")
        prevTabItem.keyEquivalentModifierMask = [.command, .option, .shift]
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc func reloadPage() {
        activeWebView?.reload()
    }

    @objc func resetZoom() {
        activeWebView?.pageZoom = 1.0
    }

    @objc func zoomIn() {
        guard let wv = activeWebView else { return }
        wv.pageZoom += 0.1
    }

    @objc func zoomOut() {
        guard let wv = activeWebView else { return }
        wv.pageZoom = max(0.5, wv.pageZoom - 0.1)
    }
}

