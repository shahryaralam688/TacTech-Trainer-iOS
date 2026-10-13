import SwiftUI
import WebKit

/// WKWebView shell for bundled Form Studio (`Resources/FormStudioWeb` via `appcontent://`).
struct FormStudioWebView: UIViewRepresentable {
    var formStudioExerciseId: String
    var onClose: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(formStudioExerciseId: formStudioExerciseId, onClose: onClose)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let userContent = config.userContentController
        userContent.add(context.coordinator, name: "formStudio")

        let handler = FormStudioLocalSchemeHandler(rootDirectory: Self.webRoot)
        config.setURLSchemeHandler(handler, forURLScheme: FormStudioLocalSchemeHandler.scheme)
        context.coordinator.schemeHandler = handler

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.965, alpha: 1)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        var components = URLComponents()
        components.scheme = FormStudioLocalSchemeHandler.scheme
        components.host = "local"
        components.path = "/index.html"
        components.queryItems = [
            URLQueryItem(name: "exercise", value: formStudioExerciseId),
            URLQueryItem(name: "mode", value: "session")
        ]
        let url = components.url ?? URL(string: "\(FormStudioLocalSchemeHandler.scheme)://local/index.html")!
        webView.load(URLRequest(url: url))
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.formStudioExerciseId = formStudioExerciseId
        context.coordinator.onClose = onClose
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "formStudio")
    }

    private static var webRoot: URL {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("FormStudioWeb", isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Folder reference may flatten into the bundle root as FormStudioWeb/
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "FormStudioWeb")?
            .deletingLastPathComponent() {
            return url
        }
        fatalError("FormStudioWeb folder missing from app bundle — add folder reference to Copy Bundle Resources")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var formStudioExerciseId: String
        var onClose: (() -> Void)?
        var schemeHandler: FormStudioLocalSchemeHandler?
        weak var webView: WKWebView?
        private var didBridgeOpen = false

        init(formStudioExerciseId: String, onClose: (() -> Void)?) {
            self.formStudioExerciseId = formStudioExerciseId
            self.onClose = onClose
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Query param usually opens via JS; evaluateJavaScript as a reliable second path.
            guard !didBridgeOpen else { return }
            didBridgeOpen = true
            let id = formStudioExerciseId
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let js = """
            (function(){
              if (window.FormStudio && typeof window.FormStudio.openExercise === 'function') {
                window.FormStudio.openExercise('\(id)');
              }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "formStudio" else { return }
            if let body = message.body as? [String: Any],
               let type = body["type"] as? String,
               type == "close" {
                DispatchQueue.main.async { [onClose] in onClose?() }
                return
            }
            if let type = message.body as? String, type == "close" {
                DispatchQueue.main.async { [onClose] in onClose?() }
            }
        }
    }
}

final class FormStudioLocalSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "appcontent"

    private let rootDirectory: URL
    private let queue = DispatchQueue(label: "FormStudioLocalSchemeHandler")

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        queue.async { [rootDirectory] in
            guard let requestURL = urlSchemeTask.request.url else {
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }

            var relativePath = requestURL.path
            if relativePath.hasPrefix("/") {
                relativePath.removeFirst()
            }
            if relativePath.isEmpty {
                relativePath = "index.html"
            }

            let fileURL = rootDirectory.appendingPathComponent(relativePath).standardizedFileURL
            guard fileURL.path.hasPrefix(rootDirectory.path) else {
                urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
                return
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let mime = Self.mimeType(for: fileURL.pathExtension)
                let response = URLResponse(
                    url: requestURL,
                    mimeType: mime,
                    expectedContentLength: data.count,
                    textEncodingName: mime.hasPrefix("text/") || mime.contains("javascript") || mime == "application/json" ? "utf-8" : nil
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "glb": return "model/gltf-binary"
        case "gltf": return "model/gltf+json"
        case "fbx": return "application/octet-stream"
        case "bin": return "application/octet-stream"
        case "wasm": return "application/wasm"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }
}
