import SwiftUI
import UIKit

/// Sandow-style Personal Info — loads/saves via `/me/profile` (+ avatar + password).
struct PersonalInformationSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var location = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var showPassword = false
    @State private var gender = "Male"
    @State private var weightKg: Double = 68
    @State private var heightCm: Double = 170
    @State private var avatarAsset: String?
    @State private var avatarURL: String?
    @State private var showAvatarPicker = false
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var toast: TTToastMessage?
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case name, email, location, currentPassword, newPassword }

    private let fieldBG = Color(white: 0.94)
    private let orange = TTColor.actionOrange
    private let avatarSize: CGFloat = 104
    private let genders = ["Male", "Female", "Non-binary", "Trans Female", "Trans Male"]

    private var isTrainee: Bool {
        store.session?.role == .trainee
    }

    var body: some View {
        VStack(spacing: 0) {
            staticHeader

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }

                    labeledField("Full Name", icon: .user, text: $name, field: .name)
                    labeledField("Email", icon: .envelope1, text: $email, field: .email, keyboard: .emailAddress)
                    passwordSection
                    if isTrainee {
                        heightSlider
                        weightSlider
                    }
                    genderRow
                    labeledField("Location", icon: .mapPin1, text: $location, field: .location)

                    saveButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .disabled(isLoading || isSaving)
            }
            .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: .white)
        }
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .ttToast($toast, bottomInset: 28)
        .task { await loadProfile() }
        .alert("Personal Info", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showAvatarPicker) {
            NavigationStack {
                AssessmentAvatarStep(
                    selection: Binding(
                        get: { avatarAsset ?? TTAvatarCatalog.default },
                        set: { avatarAsset = $0 }
                    ),
                    userId: store.session?.userId
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            Task { await commitAvatarPicker() }
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAvatarPicker = false }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var staticHeader: some View {
        ZStack(alignment: .bottom) {
            TTDarkPageHeader(title: "Personal Info") {
                dismiss()
            }

            avatarWithEdit
                .offset(y: avatarSize / 2)
        }
        .padding(.bottom, avatarSize / 2)
    }

    private var avatarWithEdit: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            localAvatarFallback
                        }
                    }
                } else {
                    localAvatarFallback
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3.5))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)

            Button { showAvatarPicker = true } label: {
                TTIcon(icon: .pencil1, filled: true, size: 12)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(orange)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .offset(y: 4)
            .accessibilityLabel("Edit avatar")
        }
    }

    @ViewBuilder
    private var localAvatarFallback: some View {
        if let avatarAsset, TTAvatarCatalog.isCustom(avatarAsset),
           let custom = TTAvatarCatalog.loadCustomImage(for: store.session?.userId) {
            Image(uiImage: custom)
                .resizable()
                .scaledToFill()
        } else if let avatarAsset, TTAvatarCatalog.isAssetName(avatarAsset) {
            Image(avatarAsset)
                .resizable()
                .scaledToFill()
        } else {
            Text(initials)
                .font(TTFont.workSans(34, weight: .bold))
                .foregroundStyle(Color(white: 0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.92))
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).map { String($0.prefix(1)) }.joined()
        return chars.isEmpty ? "?" : chars.uppercased()
    }

    // MARK: - Fields

    private func labeledField(
        _ title: String,
        icon: SandowIcon,
        text: Binding<String>,
        field: Field,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TTFont.workSans(14, weight: .bold))
                .foregroundStyle(TTColor.ink)

            HStack(spacing: 12) {
                TTIcon(icon: icon, size: 18)
                    .foregroundStyle(focusedField == field ? orange : Color(white: 0.55))
                TextField(title, text: text)
                    .font(TTFont.body(15))
                    .foregroundStyle(TTColor.ink)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                    .autocorrectionDisabled(keyboard == .emailAddress)
                    .focused($focusedField, equals: field)
                    .tint(orange)
                TTIcon(icon: .pencil1, size: 16)
                    .foregroundStyle(focusedField == field ? orange : Color(white: 0.55))
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .ttInputChrome(
                focused: focusedField == field,
                cornerRadius: 18,
                idleFill: fieldBG
            )
        }
    }

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change password")
                .font(TTFont.workSans(14, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text("Leave blank to keep your current password.")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)

            secureRow(
                placeholder: "Current password",
                text: $currentPassword,
                field: .currentPassword
            )
            secureRow(
                placeholder: "New password (min 6)",
                text: $newPassword,
                field: .newPassword
            )
        }
    }

    private func secureRow(placeholder: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 12) {
            TTIcon(icon: .lock1, size: 18)
                .foregroundStyle(Color(white: 0.55))
            Group {
                if showPassword {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            .font(TTFont.body(15))
            .focused($focusedField, equals: field)
            Button {
                showPassword.toggle()
            } label: {
                TTIcon(icon: showPassword ? .eyeSlash : .eye, size: 18)
                    .foregroundStyle(Color(white: 0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .ttInputChrome(
            focused: focusedField == field,
            cornerRadius: 18,
            idleFill: fieldBG
        )
    }

    private var heightSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Height")
                    .font(TTFont.workSans(14, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Spacer()
                Text("\(Int(heightCm)) cm")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: Int(heightCm))
            }
            Slider(value: $heightCm, in: 140...210, step: 1)
                .tint(orange)
        }
        .sensoryFeedback(.selection, trigger: Int(heightCm))
    }

    private var weightSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weight")
                    .font(TTFont.workSans(14, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Spacer()
                Text("\(Int(weightKg)) kilograms")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: Int(weightKg))
            }

            Slider(value: $weightKg, in: 35...180, step: 1)
                .tint(orange)
        }
        .sensoryFeedback(.selection, trigger: Int(weightKg))
    }

    private var genderRow: some View {
        Menu {
            ForEach(genders, id: \.self) { option in
                Button(option) { gender = option }
            }
        } label: {
            HStack(spacing: 12) {
                TTIcon(icon: genderIcon, size: 18)
                    .foregroundStyle(Color(white: 0.55))
                Text(gender)
                    .font(TTFont.body(15))
                    .foregroundStyle(TTColor.ink)
                Spacer()
                TTIcon(icon: .chevronDown, size: 13)
                    .foregroundStyle(Color(white: 0.45))
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(fieldBG)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var genderIcon: SandowIcon {
        switch gender {
        case "Female", "Trans Female": .genderFemale
        case "Male", "Trans Male": .genderMale
        default: .genderTransgender
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Save Settings")
                        .font(TTFont.workSans(17, weight: .semibold))
                    TTIcon(icon: .check, filled: true, size: 16)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isLoading)
        .padding(.top, 6)
    }

    // MARK: - Networking

    private func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await store.fetchMeProfile()
            apply(response)
        } catch {
            // Soft fallback to in-memory session so the form isn’t empty offline
            hydrateFromSession()
            errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply(_ response: MeProfileResponse) {
        name = response.user.name
        email = response.user.email
        gender = response.profile.gender
            ?? response.trainee?.gender
            ?? "Male"
        location = response.profile.location
            ?? response.trainee?.location
            ?? response.trainer?.location
            ?? ""
        if let h = response.profile.heightCm ?? response.trainee?.heightCm, h > 0 {
            heightCm = Double(h)
        }
        if let w = response.profile.weightKg ?? response.trainee?.weightKg, w > 0 {
            weightKg = w
        }
        avatarURL = response.profile.avatarUrl ?? response.user.avatarUrl
        if avatarURL?.isEmpty == true { avatarURL = nil }
        if avatarURL == nil {
            avatarAsset = response.profile.avatarAsset
                ?? response.user.avatarAsset
                ?? TTAvatarCatalog.default
        } else {
            avatarAsset = TTAvatarCatalog.customToken
        }
        currentPassword = ""
        newPassword = ""
        toast = nil
    }

    private func hydrateFromSession() {
        name = store.currentUser?.name ?? ""
        email = store.currentUser?.email ?? ""
        location = store.currentTrainee?.location ?? store.currentTrainer?.location ?? ""
        gender = store.currentTrainee?.gender ?? store.currentTrainer?.gender ?? "Male"
        if let h = store.currentTrainee?.heightCm, h > 0 { heightCm = Double(h) }
        if let w = store.currentTrainee?.weightKg, w > 0 { weightKg = w }
        avatarURL = store.remoteAvatarURL
        avatarAsset = TTAvatarCatalog.saved(for: store.session?.userId)
        currentPassword = ""
        newPassword = ""
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter your name."
            return
        }
        guard genders.contains(gender) else {
            errorMessage = "Gender is not valid."
            return
        }
        if isTrainee {
            guard (140...210).contains(Int(heightCm)) else {
                errorMessage = "Height must be between 140 and 210 cm."
                return
            }
            guard (35...180).contains(Int(weightKg)) else {
                errorMessage = "Weight must be between 35 and 180 kg."
                return
            }
        }

        let trimmedNew = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNew.isEmpty {
            guard trimmedNew.count >= 6 else {
                errorMessage = "Password must be at least 6 characters."
                return
            }
            guard !currentPassword.isEmpty else {
                errorMessage = "Enter your current password to change it."
                return
            }
        }

        isSaving = true
        toast = nil
        defer { isSaving = false }

        do {
            var body = UpdateMeProfileBody(
                name: trimmedName,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                gender: gender,
                location: location.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if isTrainee {
                body.heightCm = Int(heightCm)
                body.weightKg = weightKg
            }
            if let avatarAsset, TTAvatarCatalog.isAssetName(avatarAsset), avatarURL == nil {
                body.avatarAsset = avatarAsset
            }

            let response = try await store.saveMeProfile(body)
            apply(response)

            if !trimmedNew.isEmpty {
                try await store.changePassword(
                    currentPassword: currentPassword,
                    newPassword: trimmedNew
                )
                currentPassword = ""
                newPassword = ""
                toast = TTToastMessage(text: "Password updated", style: .success)
            } else {
                toast = TTToastMessage(text: "Saved", style: .success)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func commitAvatarPicker() async {
        guard let selection = avatarAsset else {
            showAvatarPicker = false
            return
        }
        showAvatarPicker = false
        isSaving = true
        defer { isSaving = false }

        do {
            if TTAvatarCatalog.isCustom(selection),
               let image = TTAvatarCatalog.loadCustomImage(for: store.session?.userId),
               let data = CoachImageEncoder.jpegData(from: image) ?? image.jpegData(compressionQuality: 0.88) {
                let uploaded = try await store.uploadProfileAvatar(jpegData: data, previewImage: image)
                avatarURL = uploaded.avatarUrl
                avatarAsset = TTAvatarCatalog.customToken
            } else if TTAvatarCatalog.isAssetName(selection) {
                let response = try await store.saveMeProfile(UpdateMeProfileBody(avatarAsset: selection))
                apply(response)
            }
            toast = TTToastMessage(text: "Saved", style: .success)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("Personal Information") {
    NavigationStack {
        PersonalInformationSettingsView()
            .ttPreviewTrainee()
    }
}
