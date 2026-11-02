import SwiftUI
import WebKit
import UIKit

@main
struct RidingLogApp: App {
    var body: some Scene {
        WindowGroup {
            RidingLogWebView()
                .ignoresSafeArea()
        }
    }
}

/// 記録の保存先: アプリの Documents/rides.json
/// （iPhoneのバックアップにも含まれます）
enum RideStore {
    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rides.json")
    }

    /// 保存済みのJSON文字列。まだ無い・壊れている場合は nil
    static func loadJSON() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              (try? JSONSerialization.jsonObject(with: data)) is [Any],
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    static func save(_ json: String) {
        guard let data = json.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [Any] else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

struct RidingLogWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = config.userContentController

        // 起動時に保存済みの記録をページへ渡す
        let rides = RideStore.loadJSON() ?? "null"
        let script = WKUserScript(
            source: "window.NATIVE_RIDES = \(rides);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(script)
        controller.add(context.coordinator, name: "save")
        controller.add(context.coordinator, name: "share")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.webView = webView

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "save":
                if let json = message.body as? String { RideStore.save(json) }
            case "share":
                guard let body = message.body as? [String: Any],
                      let name = body["filename"] as? String,
                      let text = body["text"] as? String else { return }
                shareCSV(name: name, text: text)
            default:
                break
            }
        }

        private func shareCSV(name: String, text: String) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { return }

            guard let view = webView,
                  var top = view.window?.rootViewController else { return }
            while let presented = top.presentedViewController { top = presented }

            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect =
                CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            top.present(sheet, animated: true)
        }
    }
}
