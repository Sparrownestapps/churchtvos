import SwiftUI
import WebKit
import AppKit

/// Hosts the shared WKWebView. The web view outlives the window, so this only re-parents it.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }
    func updateNSView(_ container: NSView, context: Context) { attach(to: container) }

    private func attach(to container: NSView) {
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}

/// The website plus the native loading bar, error page (with Retry) and download note.
struct MainWindowView: View {
    @Environment(MenuModel.self) private var model
    var web: WebModel { model.web }

    var body: some View {
        ZStack {
            WebViewHost(webView: web.webView)
            if let message = web.errorMessage {
                ErrorPage(message: message) { web.reload() } openBrowser: { NSWorkspace.shared.open(AppLinks.dashboard) }
            }
        }
        .overlay(alignment: .top) {
            if web.isLoading && web.errorMessage == nil { ProgressView().progressViewStyle(.linear).controlSize(.small).frame(maxWidth: .infinity) }
        }
        .overlay(alignment: .bottom) {
            if let note = web.downloadNote {
                HStack(spacing: 10) {
                    Image(systemName: note.url == nil ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(note.url == nil ? .orange : .green)
                    Text(note.text).lineLimit(2)
                    if let url = note.url {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
                    }
                    Button { web.downloadNote = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator))
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: web.downloadNote)
        .navigationTitle(web.title)
        .frame(minWidth: 640, minHeight: 440)
        .background(WindowFrameSaver(name: "ChurchTVMainWindow"))
        .onAppear { if web.webView.url == nil && web.errorMessage == nil { web.loadHome() } }
    }
}

struct ErrorPage: View {
    let message: String
    let retry: () -> Void
    let openBrowser: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Can't load Church TV OS").font(.title2.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            HStack {
                Button("Retry", action: retry).keyboardShortcut(.defaultAction).controlSize(.large)
                Button("Open in Browser", action: openBrowser).controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Remembers the window's size and position (NSWindow frame autosave).
struct WindowFrameSaver: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in
            guard let w = v?.window else { return }
            if w.frameAutosaveName != name { w.setFrameAutosaveName(name) }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
