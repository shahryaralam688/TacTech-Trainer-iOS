import SwiftUI
import WebKit

/// WKWebView shell for bundled Form Studio (`Resources/FormStudioWeb` via `appcontent://`).
struct FormStudioWebView: UIViewRepresentable {
    enum Presentation: Equatable {
        /// Full Form Studio chrome (instructions → guide → loop).
        case session
        /// Chrome-free looping clip for inline assessment / ambient use.
        case preview
    }

    var formStudioExerciseId: String
    /// Optional `appcontent://cache/…` or `https://…` clip URL for FBXLoader.
    var animationURL: String?
    var guideJSON: String?
    var cuesJSON: String?
    var title: String?
    var presentation: Presentation = .session
    var onClose: (() -> Void)?
    var onLoadError: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            formStudioExerciseId: formStudioExerciseId,
            animationURL: animationURL,
            guideJSON: guideJSON,
            cuesJSON: cuesJSON,
            title: title,
            presentation: presentation,
            onClose: onClose,
            onLoadError: onLoadError
        )
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

        let handler = FormStudioLocalSchemeHandler(
            rootDirectory: Self.webRoot,
            cacheDirectory: FormStudioClipCache.directory
        )
        config.setURLSchemeHandler(handler, forURLScheme: FormStudioLocalSchemeHandler.scheme)
        context.coordinator.schemeHandler = handler

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = presentation == .preview
            ? .white
            : UIColor(red: 0.95, green: 0.95, blue: 0.965, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.isUserInteractionEnabled = presentation != .preview
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
            URLQueryItem(name: "mode", value: presentation == .preview ? "preview" : "session")
        ]
        let url = components.url ?? URL(string: "\(FormStudioLocalSchemeHandler.scheme)://local/index.html")!
        webView.load(URLRequest(url: url))
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.formStudioExerciseId = formStudioExerciseId
        context.coordinator.animationURL = animationURL
        context.coordinator.guideJSON = guideJSON
        context.coordinator.cuesJSON = cuesJSON
        context.coordinator.title = title
        context.coordinator.presentation = presentation
        context.coordinator.onClose = onClose
        context.coordinator.onLoadError = onLoadError
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "formStudio")
    }

    private static var webRoot: URL {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("FormStudioWeb", isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "FormStudioWeb")?
            .deletingLastPathComponent() {
            return url
        }
        fatalError("FormStudioWeb folder missing from app bundle — add folder reference to Copy Bundle Resources")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var formStudioExerciseId: String
        var animationURL: String?
        var guideJSON: String?
        var cuesJSON: String?
        var title: String?
        var presentation: Presentation
        var onClose: (() -> Void)?
        var onLoadError: ((String) -> Void)?
        var schemeHandler: FormStudioLocalSchemeHandler?
        weak var webView: WKWebView?
        private var didBridgeOpen = false

        init(
            formStudioExerciseId: String,
            animationURL: String?,
            guideJSON: String?,
            cuesJSON: String?,
            title: String?,
            presentation: Presentation,
            onClose: (() -> Void)?,
            onLoadError: ((String) -> Void)?
        ) {
            self.formStudioExerciseId = formStudioExerciseId
            self.animationURL = animationURL
            self.guideJSON = guideJSON
            self.cuesJSON = cuesJSON
            self.title = title
            self.presentation = presentation
            self.onClose = onClose
            self.onLoadError = onLoadError
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didBridgeOpen else { return }
            didBridgeOpen = true
            bridgeOpen(on: webView)
        }

        private func bridgeOpen(on webView: WKWebView) {
            let id = formStudioExerciseId
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")

            var opts: [String: Any] = [:]
            if presentation == .preview {
                opts["preview"] = true
            }
            if let animationURL, !animationURL.isEmpty {
                opts["animationUrl"] = animationURL
            }
            if let title, !title.isEmpty {
                opts["title"] = title
            }
            if let guideJSON, let data = guideJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                opts["guide"] = obj
            }
            if let cuesJSON, let data = cuesJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                opts["cues"] = obj
            }

            let optsLiteral: String
            if opts.isEmpty {
                optsLiteral = "{}"
            } else if let data = try? JSONSerialization.data(withJSONObject: opts),
                      let s = String(data: data, encoding: .utf8) {
                optsLiteral = s
            } else {
                optsLiteral = "{}"
            }

            let js = """
            (async function(){
              try {
                if (window.FormStudio && typeof window.FormStudio.openExercise === 'function') {
                  await window.FormStudio.openExercise('\(id)', \(optsLiteral));
                }
              } catch (err) {
                try {
                  window.webkit.messageHandlers.formStudio.postMessage({
                    type: 'error',
                    message: String(err && err.message ? err.message : err)
                  });
                } catch (_) {}
              }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "formStudio" else { return }
            if let body = message.body as? [String: Any],
               let type = body["type"] as? String {
                if type == "close" {
                    DispatchQueue.main.async { [onClose] in onClose?() }
                    return
                }
                if type == "error" {
                    let detail = (body["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let text = (detail?.isEmpty == false) ? detail! : "Couldn't load 3D demo"
                    DispatchQueue.main.async { [onLoadError] in onLoadError?(text) }
                    return
                }
            }
            if let type = message.body as? String, type == "close" {
                DispatchQueue.main.async { [onClose] in onClose?() }
            }
        }
    }
}

final class FormStudioLocalSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "appcontent"
    static let cacheHost = "cache"

    private let rootDirectory: URL
    private let cacheDirectory: URL?
    private let queue = DispatchQueue(label: "FormStudioLocalSchemeHandler")

    init(rootDirectory: URL, cacheDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.cacheDirectory = cacheDirectory?.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        queue.async { [rootDirectory, cacheDirectory] in
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

            let base: URL
            if requestURL.host == Self.cacheHost {
                guard let cacheDirectory else {
                    urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                    return
                }
                base = cacheDirectory
            } else {
                base = rootDirectory
            }

            let fileURL = base.appendingPathComponent(relativePath).standardizedFileURL
            guard fileURL.path.hasPrefix(base.path) else {
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
