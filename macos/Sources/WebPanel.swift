import SwiftUI
import WebKit

// Sunucudaki bir web panelini (ör. gider paneli) konsolun içinde gösterir.
// Dosya seçme ve sürükle-bırak çalışsın diye açma paneli WKUIDelegate ile bağlanır.
struct WebPanel: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.uiDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        // Bağlantı yolu (kablo / VPN) değişince yeni adrese geç
        if view.url?.host != url.host || view.url?.port != url.port {
            view.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKUIDelegate {
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = false
            panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
        }
    }
}
