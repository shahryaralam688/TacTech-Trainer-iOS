import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Trainer verification status + submit flow (Phase 7).
struct TrainerCoachVerificationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var status: MeCoachVerification?
    @State private var isLoading = true
    @State private var missingProfile = false
    @State private var loadError: String?
    @State private var toast: TTToastMessage?
    @State private var showForm = false
    @State private var showProfileEditor = false
    @State private var isCanceling = false
    @State private var showCancelConfirm = false

    private let canvas = Color(white: 0.98)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private var isTrainer: Bool {
        store.session?.role == .trainer
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TTModalSheetHeader(
                    title: "Verification",
                    subtitle: "Free trust badge for coaches",
                    background: .white
                )

                if !isTrainer {
                    forbiddenState
                } else if isLoading && status == nil && !missingProfile {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if missingProfile {
                    missingProfileState
                } else if let loadError, status == nil {
                    errorState(loadError)
                } else if let status {
                    ScrollView(showsIndicators: false) {
                        statusContent(status)
                            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                            .padding(.top, TTModalSheetChrome.contentTopPadding)
                            .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
                    }
                    .refreshable { await load() }
                }
            }
            .background(canvas.ignoresSafeArea())
            .ttHideSystemNavigationBar()
            .ttToast($toast, bottomInset: 28)
            .task { await load() }
            .sheet(isPresented: $showForm) {
                VerificationSubmitFormView { submitted in
                    showForm = false
                    if submitted {
                        toast = TTToastMessage(
                            text: "Submitted — we’ll review shortly",
                            style: .success
                        )
                        Task { await load() }
                    }
                }
                .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showProfileEditor) {
                CoachPublicProfileEditorView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .confirmationDialog(
                "Cancel verification application?",
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel application", role: .destructive) {
                    Task { await cancelApplication() }
                }
                Button("Keep pending", role: .cancel) {}
            } message: {
                Text("You can submit again later.")
            }
        }
    }

    @ViewBuilder
    private func statusContent(_ status: MeCoachVerification) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let key = status.verificationStatus.lowercased()
            if status.isVerified || key == "approved" {
                approvedCard(status)
            } else if key == "pending" {
                pendingCard(status)
            } else if key == "rejected" {
                rejectedCard(status)
            } else if key == "revoked" {
                revokedCard(status)
            } else {
                noneCard
            }

            Text("Verification is free. We never show your documents or legal name on public profiles.")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
        }
    }

    private var noneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Get verified")
                .font(TTFont.heading(18))
            Text("Upload a government ID and coaching certification to earn a Verified badge on Find Coaches.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
            TTButton(title: "Get verified") {
                showForm = true
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func pendingCard(_ status: MeCoachVerification) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .foregroundStyle(TTColor.actionOrange)
                Text("Under review")
                    .font(TTFont.heading(18))
            }
            if let submitted = status.application?.submittedAt {
                Text("Submitted \(submitted.formatted(date: .abbreviated, time: .shortened))")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                Text("We’re reviewing your documents.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            }

            if let app = status.application {
                ownerDocsSummary(app)
            }

            if status.application?.status.lowercased() == "submitted" {
                TTButton(title: "Cancel application", style: .secondary, isLoading: isCanceling) {
                    showCancelConfirm = true
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func approvedCard(_ status: MeCoachVerification) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CoachVerifiedBadge(title: "Verified Coach")
                Spacer(minLength: 0)
            }
            Text("You’re verified")
                .font(TTFont.heading(18))
            if let at = status.verifiedAt {
                Text("Verified \(at.formatted(date: .abbreviated, time: .omitted))")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                Text("Your Verified badge appears on Find Coaches and your public profile.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func rejectedCard(_ status: MeCoachVerification) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Not approved")
                .font(TTFont.heading(18))
            if let reason = status.application?.rejectionReason?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reason.isEmpty {
                Text(reason)
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xEF4444).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("Please review your documents and submit again.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            }
            TTButton(title: "Submit again") {
                showForm = true
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func revokedCard(_ status: MeCoachVerification) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verification revoked")
                .font(TTFont.heading(18))
            Text("Your Verified badge was removed. You can submit a new application.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
            if let reason = status.application?.rejectionReason?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reason.isEmpty {
                Text(reason)
                    .font(TTFont.caption(13))
                    .foregroundStyle(TTColor.inkMuted)
            }
            TTButton(title: "Apply again") {
                showForm = true
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func ownerDocsSummary(_ app: VerificationApplication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your documents")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            ForEach(app.documents) { doc in
                HStack(spacing: 8) {
                    Image(systemName: doc.contentType.contains("pdf") ? "doc.fill" : "photo")
                        .foregroundStyle(TTColor.actionOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(docTypeLabel(doc.docType))
                            .font(TTFont.heading(13))
                        Text(doc.originalFileName ?? doc.contentType)
                            .font(TTFont.caption(11))
                            .foregroundStyle(TTColor.inkMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func docTypeLabel(_ type: String) -> String {
        switch type.lowercased() {
        case "government_id": return "Government ID"
        case "certification": return "Certification"
        case "selfie": return "Selfie"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var missingProfileState: some View {
        VStack(spacing: 16) {
            Text("Create your public coach profile first")
                .font(TTFont.heading(18))
                .multilineTextAlignment(.center)
            Text("Verification requires a coach profile.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
            TTButton(title: "Set up public profile") {
                showProfileEditor = true
            }
            .padding(.horizontal, 24)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var forbiddenState: some View {
        VStack(spacing: 12) {
            Text("Trainer only")
                .font(TTFont.heading(18))
            TTButton(title: "Close", style: .secondary) { dismiss() }
                .padding(.horizontal, 40)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { dismiss() }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn’t load verification")
                .font(TTFont.heading(18))
            Text(message)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
            TTButton(title: "Retry") {
                Task { await load() }
            }
            .padding(.horizontal, 40)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func load() async {
        guard isTrainer else {
            isLoading = false
            return
        }
        isLoading = status == nil
        loadError = nil
        missingProfile = false
        do {
            status = try await APIClient().getCoachVerification()
        } catch let error as AppError where error == .unauthorized {
            toast = TTToastMessage(text: error.localizedDescription, style: .error)
            dismiss()
        } catch let error as AppError where error.isNotFound {
            status = nil
            missingProfile = true
        } catch {
            loadError = error.localizedDescription
            toast = TTToastMessage(
                text: "Couldn’t load verification",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
        isLoading = false
    }

    @MainActor
    private func cancelApplication() async {
        isCanceling = true
        defer { isCanceling = false }
        do {
            try await APIClient().cancelCoachVerification()
            toast = TTToastMessage(text: "Application canceled", style: .success)
            await load()
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t cancel",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }
}

// MARK: - Submit form

private struct VerificationSubmitFormView: View {
    var onFinished: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var legalName = ""
    @State private var countryCode = "PK"
    @State private var attestation = false
    @State private var govID = UploadDraft(docType: "government_id")
    @State private var certification = UploadDraft(docType: "certification")
    @State private var selfie = UploadDraft(docType: "selfie")
    @State private var isSubmitting = false
    @State private var toast: TTToastMessage?
    @State private var activePicker: UploadDraft.ID?
    @State private var showSourceDialog = false
    @State private var showPhotosPicker = false
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?

    private let canvas = Color(white: 0.98)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let maxBytes = 10 * 1024 * 1024
    private let allowedImportTypes: [UTType] = {
        var types: [UTType] = [.pdf, .jpeg, .png, .image]
        if let webp = UTType(filenameExtension: "webp") { types.append(webp) }
        if let heic = UTType(filenameExtension: "heic") { types.append(heic) }
        return types
    }()

    private var canSubmit: Bool {
        !legalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && countryCode.trimmingCharacters(in: .whitespacesAndNewlines).count == 2
            && attestation
            && govID.isUploaded
            && certification.isUploaded
            && !isSubmitting
            && !govID.isUploading
            && !certification.isUploading
            && !selfie.isUploading
    }

    var body: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(
                title: "Get verified",
                subtitle: "ID + certification required",
                background: .white
            ) {
                Button("Close") {
                    onFinished(false)
                    dismiss()
                }
                .font(TTFont.heading(14))
                .foregroundStyle(TTColor.inkMuted)
                .frame(width: TTModalSheetChrome.controlSize, height: TTModalSheetChrome.controlSize)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    TTTextField(title: "Legal full name", icon: "person", text: $legalName)
                    TTTextField(title: "Country code", icon: "globe", text: $countryCode)

                    uploadCard(title: "Government ID", required: true, draft: $govID)
                    uploadCard(title: "Certification", required: true, draft: $certification)
                    uploadCard(title: "Selfie (optional)", required: false, draft: $selfie)

                    Toggle(isOn: $attestation) {
                        Text("I confirm this information is accurate")
                            .font(TTFont.body(14))
                    }
                    .tint(TTColor.actionOrange)
                    .padding(14)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    TTButton(title: "Submit for review", isLoading: isSubmitting) {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.55)
                }
                .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                .padding(.top, TTModalSheetChrome.contentTopPadding)
                .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .ttToast($toast, bottomInset: 28)
        .confirmationDialog(
            "Add document",
            isPresented: $showSourceDialog,
            titleVisibility: .visible
        ) {
            Button("Photo library") { showPhotosPicker = true }
            Button("Files (PDF / image)") { showFileImporter = true }
            Button("Cancel", role: .cancel) { activePicker = nil }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item, let id = activePicker else { return }
            Task { await handlePhoto(item, for: id) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedImportTypes,
            allowsMultipleSelection: false
        ) { result in
            guard let id = activePicker else { return }
            Task { await handleFileImport(result, for: id) }
        }
    }

    private func uploadCard(title: String, required: Bool, draft: Binding<UploadDraft>) -> some View {
        let value = draft.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(TTFont.heading(14))
                if required {
                    Text("Required")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.actionOrange)
                }
                Spacer()
            }

            if value.isUploaded {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: 0x22C55E))
                    Text(value.fileName ?? "Uploaded")
                        .font(TTFont.body(13))
                        .lineLimit(1)
                    Spacer()
                    Button("Replace") {
                        beginPick(value.id)
                    }
                    .font(TTFont.heading(13))
                    .foregroundStyle(TTColor.actionOrange)
                }
            } else if value.isUploading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Uploading…")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
            } else if let error = value.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(TTFont.caption(12))
                        .foregroundStyle(Color(hex: 0xEF4444))
                    Button("Retry") {
                        beginPick(value.id)
                    }
                    .font(TTFont.heading(13))
                    .foregroundStyle(TTColor.actionOrange)
                }
            } else {
                Button {
                    beginPick(value.id)
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.doc")
                        Text("Upload file")
                            .font(TTFont.heading(14))
                    }
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(TTColor.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func beginPick(_ id: UploadDraft.ID) {
        activePicker = id
        showSourceDialog = true
    }

    @MainActor
    private func handlePhoto(_ item: PhotosPickerItem, for id: UploadDraft.ID) async {
        defer {
            photoItem = nil
            showPhotosPicker = false
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                setError(id, "Couldn’t read photo")
                return
            }
            let jpeg = CoachImageEncoder.jpegData(from: data) ?? data
            let name = "photo-\(id).jpg"
            await upload(id: id, data: jpeg, contentType: "image/jpeg", fileName: name)
        } catch {
            setError(id, error.localizedDescription)
        }
    }

    @MainActor
    private func handleFileImport(_ result: Result<[URL], Error>, for id: UploadDraft.ID) async {
        switch result {
        case .failure(let error):
            setError(id, error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let (contentType, fileName, payload) = try prepareFile(data: data, url: url)
                await upload(id: id, data: payload, contentType: contentType, fileName: fileName)
            } catch {
                setError(id, error.localizedDescription)
            }
        }
        activePicker = nil
    }

    private func prepareFile(data: Data, url: URL) throws -> (String, String, Data) {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        let pdfMagic = Data("%PDF".utf8)
        let isPDF = ext == "pdf" || data.prefix(pdfMagic.count) == pdfMagic
        if isPDF {
            guard data.count <= maxBytes else {
                throw AppError.validation("File must be 10 MB or smaller.")
            }
            return ("application/pdf", name, data)
        }
        if let jpeg = CoachImageEncoder.jpegData(from: data) {
            guard jpeg.count <= maxBytes else {
                throw AppError.validation("File must be 10 MB or smaller.")
            }
            let base = url.deletingPathExtension().lastPathComponent
            return ("image/jpeg", "\(base).jpg", jpeg)
        }
        let type: String
        switch ext {
        case "png": type = "image/png"
        case "webp": type = "image/webp"
        case "heic", "heif": type = "image/heic"
        case "jpg", "jpeg": type = "image/jpeg"
        default:
            throw AppError.validation("Use a photo or PDF.")
        }
        guard data.count <= maxBytes else {
            throw AppError.validation("File must be 10 MB or smaller.")
        }
        return (type, name, data)
    }

    @MainActor
    private func upload(id: UploadDraft.ID, data: Data, contentType: String, fileName: String) async {
        guard data.count <= maxBytes else {
            setError(id, "File must be 10 MB or smaller.")
            return
        }
        mutate(id) {
            $0.isUploading = true
            $0.error = nil
            $0.fileName = fileName
        }
        let docType = draft(for: id)?.docType ?? "other"
        do {
            let api = APIClient()
            let slot = try await api.createVerifyUpload(
                docType: docType,
                contentType: contentType,
                fileName: fileName
            )
            let put = try await api.putVerifyUpload(
                uploadUrl: slot.uploadUrl,
                data: data,
                contentType: contentType
            )
            let key = put.fileKey?.nilIfBlank ?? slot.fileKey
            guard !key.isEmpty else {
                throw AppError.api("Upload succeeded but file key was missing.")
            }
            mutate(id) {
                $0.isUploading = false
                $0.fileKey = key
                $0.contentType = contentType
                $0.fileName = fileName
                $0.error = nil
            }
            activePicker = nil
        } catch {
            mutate(id) {
                $0.isUploading = false
                $0.fileKey = nil
                $0.error = error.localizedDescription
            }
            toast = TTToastMessage(
                text: "Upload failed",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let body = VerificationSubmitBody(
            legalFullName: legalName.trimmingCharacters(in: .whitespacesAndNewlines),
            countryCode: countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            attestationAccepted: true,
            documents: [
                VerificationDocRef(
                    docType: "government_id",
                    fileKey: govID.fileKey ?? "",
                    contentType: govID.contentType ?? "image/jpeg",
                    originalFileName: govID.fileName
                ),
                VerificationDocRef(
                    docType: "certification",
                    fileKey: certification.fileKey ?? "",
                    contentType: certification.contentType ?? "image/jpeg",
                    originalFileName: certification.fileName
                )
            ] + (selfie.isUploaded
                ? [VerificationDocRef(
                    docType: "selfie",
                    fileKey: selfie.fileKey ?? "",
                    contentType: selfie.contentType ?? "image/jpeg",
                    originalFileName: selfie.fileName
                )]
                : [])
        )
        do {
            _ = try await APIClient().submitCoachVerification(body)
            onFinished(true)
            dismiss()
        } catch let error as AppError where error.isConflict {
            toast = TTToastMessage(
                text: error.localizedDescription,
                style: .error
            )
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t submit",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    private func draft(for id: UploadDraft.ID) -> UploadDraft? {
        if govID.id == id { return govID }
        if certification.id == id { return certification }
        if selfie.id == id { return selfie }
        return nil
    }

    private func mutate(_ id: UploadDraft.ID, _ update: (inout UploadDraft) -> Void) {
        if govID.id == id { update(&govID) }
        else if certification.id == id { update(&certification) }
        else if selfie.id == id { update(&selfie) }
    }

    private func setError(_ id: UploadDraft.ID, _ message: String) {
        mutate(id) {
            $0.isUploading = false
            $0.error = message
        }
        activePicker = nil
    }
}

private struct UploadDraft: Identifiable, Equatable {
    let id: String
    var docType: String
    var fileKey: String?
    var contentType: String?
    var fileName: String?
    var isUploading = false
    var error: String?

    init(docType: String) {
        self.id = docType
        self.docType = docType
    }

    var isUploaded: Bool {
        !(fileKey ?? "").isEmpty
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#Preview("Verification") {
    TrainerCoachVerificationView()
        .ttPreviewTrainer()
}
