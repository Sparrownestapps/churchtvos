import AppKit
import WebKit
import Observation
import UniformTypeIdentifiers
import ChurchTVCore

/// What the session bridge found in the website's localStorage.
enum BridgeReading: Equatable {
    case session(WebSession)
    case signedOut          // the website is loaded and holds no session
    case unavailable        // page not loaded (yet), offline, or on another origin: say nothing
}

/// Short message under the page after a download finished or failed. `url` is the saved file (nil on failure).
struct DownloadNote: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let url: URL?
}

/// Owns the single WKWebView that shows https://app.churchtvos.com. It lives for the whole app run, also while the window is closed,
/// so the website's own sign-in refresh keeps working and the menu bar can read the session.
@MainActor
@Observable
final class WebModel: NSObject {
    static let zoomKey = "pageZoom"

    @ObservationIgnored let webView: WKWebView
    var title = "Church TV OS"
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var errorMessage: String?
    var downloadNote: DownloadNote?
    var currentURL: URL?
    private(set) var zoom: Double

    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    @ObservationIgnored private var noteTask: Task<Void, Never>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // persistent: the web sign-in survives restarts
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        config.applicationNameForUserAgent = "ChurchTVOSMac/\(v)"
        config.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: config)
        let saved = UserDefaults.standard.double(forKey: Self.zoomKey)
        zoom = saved >= 0.5 && saved <= 3 ? saved : 1
        super.init()
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.allowsBackForwardNavigationGestures = true
        webView.pageZoom = zoom
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observers = [
            webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                let t = wv.title ?? ""
                Task { @MainActor in self?.title = t.isEmpty ? "Church TV OS" : t }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                let b = wv.canGoBack; Task { @MainActor in self?.canGoBack = b }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                let b = wv.canGoForward; Task { @MainActor in self?.canGoForward = b }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                let b = wv.isLoading; Task { @MainActor in self?.isLoading = b }
            },
            webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                let u = wv.url; Task { @MainActor in self?.currentURL = u }
            },
        ]
    }

    // MARK: Navigation

    /// Home page. `-url <https://app.churchtvos.com/...>` (test helper) opens another page of the website at launch.
    func loadHome() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-url"), i + 1 < args.count, let u = URL(string: args[i + 1]), LinkRouter.isInternal(u), webView.url == nil {
            load(u)
        } else { load(AppLinks.dashboard) }
    }

    func load(_ url: URL) {
        errorMessage = nil
        webView.load(URLRequest(url: url))
    }

    /// Opens a website section. Uses the hash route when the app is already loaded, else loads the site at that route.
    func open(_ section: AppLinks.Section) {
        if LinkRouter.isInternal(webView.url), errorMessage == nil {
            webView.evaluateJavaScript("location.hash = '\(section.rawValue)'", completionHandler: nil)
        } else {
            load(URL(string: AppLinks.dashboard.absoluteString + "#" + section.rawValue)!)
        }
    }

    /// Opens any hash route of the website ("sites", "songs", ...).
    func openRoute(_ route: String) {
        if LinkRouter.isInternal(webView.url), errorMessage == nil {
            webView.evaluateJavaScript("location.hash = '\(route.filter { $0.isLetter || $0.isNumber || $0 == "-" })'", completionHandler: nil)
        } else {
            load(URL(string: AppLinks.dashboard.absoluteString + "#" + route)!)
        }
    }

    func reload() {
        if errorMessage != nil || webView.url == nil { loadHome() } else { webView.reload() }
    }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func setZoom(_ z: Double) {
        zoom = min(3, max(0.5, (z * 100).rounded() / 100))
        webView.pageZoom = zoom
        UserDefaults.standard.set(zoom, forKey: Self.zoomKey)
    }
    func zoomIn() { setZoom(zoom + 0.1) }
    func zoomOut() { setZoom(zoom - 0.1) }
    func resetZoom() { setZoom(1) }

    // MARK: Session bridge

    /// Reads the supabase-js session from the website's localStorage. Never logs the result.
    func readSession() async -> BridgeReading {
        guard LinkRouter.isInternal(webView.url), !webView.isLoading, errorMessage == nil else { return .unavailable }
        do {
            let result = try await webView.evaluateJavaScript(WebSessionBridge.readScript)
            guard let raw = result as? String else { return .unavailable }
            if let session = WebSessionBridge.parse(raw) { return .session(session) }
            return .signedOut
        } catch {
            return .unavailable
        }
    }

    /// Removes the website's stored session (Mac-side sign out) and reloads so the login page shows.
    func clearSessionAndReload() async {
        if LinkRouter.isInternal(webView.url) {
            _ = try? await webView.evaluateJavaScript(WebSessionBridge.clearScript)
        }
        loadHome()
    }

    // MARK: Helpers

    private func fail(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }   // "Frame load interrupted" (a download started)
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed:
                errorMessage = "You appear to be offline. Check your internet connection and try again."
            case NSURLErrorTimedOut:
                errorMessage = "The website took too long to answer."
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                errorMessage = "Church TV OS could not be reached right now."
            default:
                errorMessage = "The page could not be loaded (\(ns.localizedDescription))."
            }
        } else {
            errorMessage = "The page could not be loaded (\(ns.localizedDescription))."
        }
    }

    private func flash(_ text: String, url: URL?) {
        downloadNote = DownloadNote(text: text, url: url)
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { self?.downloadNote = nil }
        }
    }

    private func openExternally(_ url: URL) {
        guard LinkRouter.isSafeToOpenExternally(url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func presentAlert(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        if let window = webView.window { return await alert.beginSheetModal(for: window) }
        return alert.runModal()
    }

    private func hostLabel(_ frame: WKFrameInfo) -> String { frame.request.url?.host ?? "Church TV OS" }

    /// Unique file name inside Downloads ("report.csv", "report 2.csv", ...).
    private func uniqueDestination(_ name: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
        let safe = (name as NSString).lastPathComponent.isEmpty ? "download" : (name as NSString).lastPathComponent
        var candidate = dir.appendingPathComponent(safe)
        let ext = candidate.pathExtension, base = candidate.deletingPathExtension().lastPathComponent
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

// MARK: - Navigation

extension WebModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if navigationAction.shouldPerformDownload { return (.download, preferences) }
        let url = navigationAction.request.url
        let decision = LinkRouter.decide(url: url, opensNewWindow: navigationAction.targetFrame == nil,
                                         isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true)
        switch decision {
        case .allow: return (.allow, preferences)
        case .openExternally:
            if let url { openExternally(url) }
            return (.cancel, preferences)
        case .cancel: return (.cancel, preferences)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if let http = navigationResponse.response as? HTTPURLResponse, navigationResponse.isForMainFrame {
            if let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(), disposition.hasPrefix("attachment") { return .download }
            if http.statusCode >= 500 {
                errorMessage = "The website is having a problem right now (error \(http.statusCode)). Try again in a moment."
                return .cancel
            }
        }
        return navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { errorMessage = nil }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
}

// MARK: - UI (new windows, JavaScript dialogs, file picker)

extension WebModel: WKUIDelegate {
    /// target=_blank and window.open: the default browser handles them; nothing opens inside the app.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url,
           LinkRouter.decide(url: url, opensNewWindow: true) == .openExternally { openExternally(url) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = hostLabel(frame)
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        _ = await presentAlert(alert)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = hostLabel(frame)
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return await presentAlert(alert) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = NSAlert()
        alert.messageText = hostLabel(frame)
        alert.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return await presentAlert(alert) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.message = "Choose files to upload to Church TV OS"
        let response: NSApplication.ModalResponse
        if let window = webView.window { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
        return response == .OK ? panel.urls : nil
    }
}

// MARK: - Downloads

extension WebModel: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard let dest = uniqueDestination(suggestedFilename) else { return nil }
        downloadDestinations[ObjectIdentifier(download)] = dest
        return dest
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let dest = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) { flash("Saved \(dest.lastPathComponent) to Downloads", url: dest) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        flash("The download failed (\(error.localizedDescription)).", url: nil)
    }
}
