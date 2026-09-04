import SwiftUI

/// Sandow-style Personal Info — static dark header + overlapping avatar; form scrolls below.
struct PersonalInformationSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var location = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var passwordFocused = false
    @State private var gender = "Male"
    @State private var weightKg: Double = 68
    @State private var accountType = "Regular"
    @State private var avatarAsset: String?
    @State private var showAvatarPicker = false
    @State private var showSettings = false
    @State private var saved = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, email, location, password }

    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let fieldBG = Color(white: 0.94)
    private let orange = TTColor.actionOrange
    private let selectBlue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    private let headerHeight: CGFloat = 168
    private let avatarSize: CGFloat = 104
    private let genders = ["Male", "Female", "Non-binary", "Trans Female", "Trans Male"]
    private let accountTypes = ["Regular", "Coach", "Nutritionist"]

    var body: some View {
        VStack(spacing: 0) {
            staticHeader

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    labeledField("Full Name", icon: .user, text: $name, field: .name)
                    labeledField("Email", icon: .envelope1, text: $email, field: .email, keyboard: .emailAddress)
                    passwordField
                    weightSlider
                    genderRow
                    labeledField("Location", icon: .mapPin1, text: $location, field: .location)
                    accountTypeRow

                    if saved {
                        Text("Saved")
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.success)
                            .frame(maxWidth: .infinity)
                    }

                    saveButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .ttHideSystemNavigationBar()
        .onAppear(perform: hydrate)
        .sheet(isPresented: $showAvatarPicker) {
            NavigationStack {
                AssessmentAvatarStep(selection: Binding(
                    get: { avatarAsset ?? TTAvatarCatalog.default },
                    set: { avatarAsset = $0 }
                ))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if let avatarAsset {
                                TTAvatarCatalog.save(avatarAsset, for: store.session?.userId)
                            }
                            showAvatarPicker = false
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAvatarPicker = false }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showSettings) {
            AccountSettingsView()
        }
    }

    // MARK: - Static header

    private var staticHeader: some View {
        ZStack(alignment: .top) {
            charcoal
                .frame(height: headerHeight)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 36,
                        bottomTrailingRadius: 36,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )

            HStack {
                chromeButton(icon: .chevronLeft) { dismiss() }
                Spacer()
                Text("Personal Info")
                    .font(TTFont.workSans(17, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                chromeButton(icon: .gear1) { showSettings = true }
            }
            .padding(.horizontal, 18)
            .padding(.top, 58)

            VStack(spacing: 0) {
                Color.clear.frame(height: headerHeight - avatarSize / 2)
                avatarWithEdit
            }
        }
        .padding(.bottom, 8)
    }

    private var avatarWithEdit: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let avatarAsset, TTAvatarCatalog.isAssetName(avatarAsset) {
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

    private func chromeButton(icon: SandowIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TTIcon(icon: icon, filled: true, size: 18)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(Color(white: 0.55))
                TextField(title, text: text)
                    .font(TTFont.body(15))
                    .foregroundStyle(TTColor.ink)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                    .autocorrectionDisabled(keyboard == .emailAddress)
                    .focused($focusedField, equals: field)
                TTIcon(icon: .pencil1, size: 16)
                    .foregroundStyle(Color(white: 0.55))
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(fieldBG)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password")
                .font(TTFont.workSans(14, weight: .bold))
                .foregroundStyle(TTColor.ink)

            HStack(spacing: 12) {
                TTIcon(icon: .lock1, size: 18)
                    .foregroundStyle(Color(white: 0.55))
                Group {
                    if showPassword {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .font(TTFont.body(15))
                .focused($focusedField, equals: .password)
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
            .background(fieldBG)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(focusedField == .password ? orange : .clear, lineWidth: 1.5)
            )
        }
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
            }

            Slider(value: $weightKg, in: 35...180, step: 1)
                .tint(orange)
        }
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
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

    private var accountTypeRow: some View {
        HStack(spacing: 8) {
            ForEach(accountTypes, id: \.self) { type in
                let on = accountType == type
                Button {
                    accountType = type
                } label: {
                    HStack(spacing: 6) {
                        Text(type)
                            .font(TTFont.workSans(13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Image(systemName: on ? "checkmark.square.fill" : "circle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(on ? .white : TTColor.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(on ? selectBlue : fieldBG)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: 8) {
                Text("Save Settings")
                    .font(TTFont.workSans(17, weight: .semibold))
                TTIcon(icon: .check, filled: true, size: 16)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    // MARK: - Data

    private func hydrate() {
        name = store.currentUser?.name ?? ""
        email = store.currentUser?.email ?? ""
        location = store.currentTrainee?.location ?? store.currentTrainer?.location ?? ""
        gender = store.currentTrainee?.gender ?? store.currentTrainer?.gender ?? "Male"
        if let w = store.currentTrainee?.weightKg, w > 0 { weightKg = w }
        avatarAsset = TTAvatarCatalog.saved(for: store.session?.userId)
        if store.session?.role == .trainer {
            accountType = "Coach"
        } else {
            accountType = UserDefaults.standard.string(forKey: accountTypeKey) ?? "Regular"
        }
        password = ""
    }

    private var accountTypeKey: String {
        "profile.accountType.\(store.session?.userId ?? "x")"
    }

    private func save() {
        store.updateCurrentUserName(name)
        store.applyProfileSetup(
            gender: gender,
            location: location,
            heightCm: store.currentTrainee?.heightCm,
            weightKg: store.session?.role == .trainee ? weightKg : nil
        )
        if let avatarAsset {
            TTAvatarCatalog.save(avatarAsset, for: store.session?.userId)
        }
        UserDefaults.standard.set(accountType, forKey: accountTypeKey)
        saved = true
    }
}

#Preview("Personal Information") {
    NavigationStack {
        PersonalInformationSettingsView()
            .ttPreviewTrainee()
    }
}
