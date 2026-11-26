import AVFoundation
import Charts
import ImageIO
import PhotosUI
import SwiftUI
import Vision

// MARK: Barcode (on device)

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

enum NutBarcode {
    /// The first barcode in the image (Apple Vision, no network).
    static func detect(in image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> String? in
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            do { try handler.perform([request]) } catch { return nil }
            return request.results?.compactMap { $0.payloadStringValue }.first { !$0.isEmpty }
        }.value
    }
}

// MARK: Nutrition label OCR (on device)

enum NutLabelOCR {
    /// All text Vision can read from a label photo, one line per row. Runs off the main actor.
    static func recognize(in image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            do { try handler.perform([request]) } catch { return "" }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}

// MARK: Capture panel: photos → (barcode fast path) → disclosure → analyze → tray

struct NutCaptureContent: View {
    @Environment(AppStore.self) private var store
    let firstPhoto: UIImage
    /// Optional: the first photo is a nutrition label, so run label OCR right away.
    var startsWithLabelScan = false
    let close: (_ after: (() -> Void)?) -> Void
    let onSaved: (TTToastMessage) -> Void
    let onSearch: () -> Void

    private enum Phase: Equatable {
        case checkingBarcode, collecting, disclosure, analyzing, readingLabel, notFound(String), tray
    }

    private static let disclosureKey = "nutrition.aiPhotoDisclosureAccepted"

    @State private var photos: [UIImage] = []
    @State private var phase: Phase = .checkingBarcode
    @State private var trayItems: [NutTrayItem] = []
    @State private var trayTag: String?
    @State private var traySource = "photo"
    @State private var analysisTask: Task<Void, Never>?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var cameraImage: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var cameraMessage: String?
    /// The next picked photo is a nutrition label (OCR), not a meal photo.
    @State private var pickingLabel = false
    /// A barcode was read but is not in the database: the not-found screen offers "Scan nutrition label".
    @State private var barcodeMissed = false
    /// Optional one-line note for the analysis ("zero sugar", "air fried"). Never required.
    @State private var hint = ""

    var body: some View {
        Group {
            switch phase {
            case .checkingBarcode: busy("Checking barcode…")
            case .collecting: collecting
            case .disclosure: disclosure
            case .analyzing: analyzing
            case .readingLabel: readingLabel
            case .notFound(let message): notFound(message)
            case .tray:
                NutMealTrayContent(items: trayItems, mealTag: trayTag, source: traySource, heroPhoto: photos.first, close: close, onSaved: onSaved)
            }
        }
        .task { await start() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(image: $cameraImage).ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: cameraImage) { _, image in
            guard let image else { return }
            cameraImage = nil
            handlePicked(image)
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                defer { libraryItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    handlePicked(image)
                }
            }
        }
        .onDisappear { analysisTask?.cancel() }
    }

    // MARK: Phases

    private func busy(_ title: LocalizedStringKey) -> some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(title)
                .font(TTFont.workSans(16, weight: .semibold)).foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }

    private var analyzing: some View {
        VStack(spacing: 10) {
            busy("Looking at your photo…")
            nutPanelButton("Cancel", style: .ghost) {
                analysisTask?.cancel()
                phase = .collecting
            }
        }
    }

    private var readingLabel: some View {
        VStack(spacing: 10) {
            busy("Reading the label…")
            nutPanelButton("Cancel", style: .ghost) {
                analysisTask?.cancel()
                phase = .collecting
            }
        }
    }

    /// "Scan nutrition label": take or pick a photo of the label; the text is read on the device.
    private func labelScanMenu() -> some View {
        Menu {
            Button { pickingLabel = true; openCamera() } label: { Text("Take photo") }
            Button { pickingLabel = true; showLibrary = true } label: { Text("Choose photo") }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder").font(.system(size: 15, weight: .semibold))
                Text("Scan nutrition label").font(TTFont.workSans(15, weight: .semibold))
            }
            .foregroundStyle(NutStyle.accentText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private var collecting: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add photos")
                .font(TTFont.workSans(20, weight: .bold)).foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Add up to 5 photos of the same meal.")
                .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                .padding(.top, 2).padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityLabel(Text("Meal photo"))
                            Button { photos.remove(at: index) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Color.black.opacity(0.75))
                                    .clipShape(Circle())
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove photo"))
                            .offset(x: 14, y: -14)
                        }
                        .frame(width: 84, height: 84)
                    }
                    if photos.count < 5 { addTile }
                }
                .padding(.top, 14).padding(.trailing, 16).padding(.bottom, 6)
            }

            if let cameraMessage {
                Text(verbatim: cameraMessage).font(TTFont.body(13)).foregroundStyle(NutStyle.mute).padding(.bottom, 6)
            }

            TextField("Optional note (e.g. zero sugar, air fried, chicken)", text: $hint)
                .font(TTFont.body(15))
                .lineLimit(1)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(NutStyle.field)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
                .onChange(of: hint) { _, value in
                    if value.count > 200 { hint = String(value.prefix(200)) }
                }
                .accessibilityLabel(Text("Optional note"))

            nutPanelButton("Analyze", style: .primary) { analyze() }
                .disabled(photos.isEmpty)
                .opacity(photos.isEmpty ? 0.4 : 1)
                .padding(.top, 8)
            labelScanMenu()
            nutPanelButton("Cancel", style: .ghost) { close(nil) }
        }
    }

    private var addTile: some View {
        Menu {
            Button { openCamera() } label: { Text("Take photo") }
            Button { showLibrary = true } label: { Text("Choose photo") }
        } label: {
            VStack(spacing: 4) {
                TTIcon(icon: .camera1, size: 20)
                Text("+ Add photo")
                    .font(TTFont.workSans(12, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(NutStyle.accentText)
            .frame(width: 84, height: 84)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(NutStyle.orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .accessibilityLabel(Text("Add photo"))
    }

    private var disclosure: some View {
        VStack(spacing: 0) {
            TTIcon(icon: .camera1, size: 28)
                .foregroundStyle(NutStyle.orange)
                .frame(width: 64, height: 64)
                .background(Color(red: 1, green: 241 / 255, blue: 230 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 6).padding(.bottom, 10)
                .accessibilityHidden(true)
            Text("AI photo analysis")
                .font(TTFont.workSans(20, weight: .bold)).foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Meal photos are analyzed by AI to estimate calories and macros. Photos are not used to train AI models.")
                .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                .multilineTextAlignment(.center)
                .padding(.top, 2).padding(.bottom, 10)
            nutPanelButton("Continue", style: .primary) {
                UserDefaults.standard.set(true, forKey: Self.disclosureKey)
                runAnalysis()
            }
            nutPanelButton("Cancel", style: .ghost) { phase = .collecting }
        }
        .frame(maxWidth: .infinity)
    }

    private func notFound(_ message: String) -> some View {
        VStack(spacing: 10) {
            TTIcon(icon: .infoCircle, size: 28)
                .foregroundStyle(TTColor.inkMuted)
                .padding(.top, 6)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(TTFont.body(15)).foregroundStyle(TTColor.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8).padding(.bottom, 6)
            nutPanelButton("Search", style: .primary) { onSearch() }
            if barcodeMissed { labelScanMenu() }
            nutPanelButton("Retake", style: .ghost) {
                photos = []
                phase = .collecting
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func start() async {
        guard photos.isEmpty else { return }
        if startsWithLabelScan {
            scanLabel(firstPhoto)
            return
        }
        photos = [firstPhoto]
        // On-device barcode fast path: a found barcode costs no AI call.
        guard let code = await NutBarcode.detect(in: firstPhoto) else {
            phase = .collecting
            return
        }
        phase = .checkingBarcode
        do {
            let response = try await store.lookupBarcode(code)
            if response.found == true, let item = response.item, let tray = NutTrayBuilder.item(from: item) {
                trayItems = [tray]
                trayTag = nil
                traySource = "barcode"
                phase = .tray
            } else {
                barcodeMissed = true
                phase = .notFound(String(localized: "Barcode not found — take a photo of the food or search."))
            }
        } catch {
            phase = .notFound(String(localized: "Couldn’t analyze right now. Check your connection, or search for the food instead."))
        }
    }

    private func handlePicked(_ image: UIImage) {
        if pickingLabel {
            pickingLabel = false
            scanLabel(image)
        } else {
            addPhoto(image)
        }
    }

    /// Label photo → text on the device (Vision) → `parse-label` → Meal Tray with a Verified Label item.
    private func scanLabel(_ image: UIImage) {
        phase = .readingLabel
        analysisTask?.cancel()
        analysisTask = Task {
            let text = await NutLabelOCR.recognize(in: image)
            if Task.isCancelled { return }
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 else {
                phase = .notFound(String(localized: "Couldn’t read this label — retake the photo or search."))
                return
            }
            do {
                let response = try await store.parseNutritionLabel(ocrText: text)
                if Task.isCancelled { return }
                if response.found == true, let item = response.item, let tray = NutTrayBuilder.item(from: item) {
                    trayItems = [tray]
                    trayTag = nil
                    traySource = "label"
                    phase = .tray
                } else {
                    phase = .notFound(String(localized: "Couldn’t read this label — retake the photo or search."))
                }
            } catch {
                if Task.isCancelled { return }
                phase = .notFound(String(localized: "Couldn’t analyze right now. Check your connection, or search for the food instead."))
            }
        }
    }

    private func addPhoto(_ image: UIImage) {
        guard photos.count < 5 else { return }
        photos.append(image)
        if phase != .collecting { phase = .collecting }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { showLibrary = true; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        cameraMessage = String(localized: "Camera access is off — choose a photo from your library.")
                        showLibrary = true
                    }
                }
            }
        default:
            cameraMessage = String(localized: "Camera access is off — choose a photo from your library.")
            showLibrary = true
        }
    }

    private func analyze() {
        guard !photos.isEmpty else { return }
        // First cloud analysis: one-time AI disclosure (App Store guideline 5.1.2).
        if UserDefaults.standard.bool(forKey: Self.disclosureKey) {
            runAnalysis()
        } else {
            phase = .disclosure
        }
    }

    private func runAnalysis() {
        phase = .analyzing
        analysisTask?.cancel()
        let images = photos
        let note = hint
        analysisTask = Task {
            do {
                let result = try await store.analyzeMealPhotos(images, hint: note)
                if Task.isCancelled { return }
                let mapped = (result.items ?? []).map { NutTrayBuilder.item(from: $0) }
                if result.isFood == false || mapped.isEmpty {
                    let message = (result.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    phase = .notFound(message.isEmpty ? String(localized: "We couldn’t recognise a meal in this photo.") : message)
                    return
                }
                trayItems = mapped
                trayTag = result.mealTag
                traySource = "photo"
                phase = .tray
            } catch {
                if Task.isCancelled { return }
                phase = .notFound(String(localized: "Couldn’t analyze right now. Check your connection, or search for the food instead."))
            }
        }
    }
}

extension Notification.Name {
    /// A meal was saved outside the Nutrition screen (Home, + menu).
    static let ttMealSaved = Notification.Name("ttMealSaved")
}

/// Home and the + menu: the same Add photos → barcode / AI → Review your meal flow as Nutrition, in a normal sheet.
struct TTMealPhotoFlowSheet: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    var onSaved: (TTToastMessage) -> Void
    /// "Search" on the not-found screen: called after this sheet has closed.
    var onSearch: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255))
                .frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 10)
                .accessibilityHidden(true)
            ScrollView {
                NutCaptureContent(
                    firstPhoto: image,
                    close: { after in dismiss(); after?() },
                    onSaved: { toast in
                        NotificationCenter.default.post(name: .ttMealSaved, object: nil)
                        onSaved(toast)
                    },
                    onSearch: {
                        dismiss()
                        if let onSearch {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onSearch() }
                        }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.white.ignoresSafeArea())
    }
}
