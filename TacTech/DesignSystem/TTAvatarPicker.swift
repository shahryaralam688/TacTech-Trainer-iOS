import PhotosUI
import SwiftUI
import UIKit

/// Packaged avatar illustrations + optional custom gallery/camera photo per user.
enum TTAvatarCatalog {
    static let all: [String] = [
        "Avatar_01_Color", "Avatar_02_Color", "Avatar_03_Color", "Avatar_04_Color",
        "Avatar_05_Color", "Avatar_06_Color", "Avatar_07_Color", "Avatar_08_Color",
        "Avatar_09_Color", "Avatar_10_Color",
        "Avatar_11_Grayscale", "Avatar_12_Grayscale", "Avatar_13_Grayscale",
        "Avatar_14_Grayscale", "Avatar_15_Grayscale", "Avatar_16_Grayscale",
        "Avatar_17_Grayscale", "Avatar_18_Grayscale", "Avatar_19_Grayscale",
        "Avatar_20_Grayscale"
    ]

    static let `default` = "Avatar_01_Color"
    /// Selection token for a user-uploaded photo stored on disk.
    static let customToken = "custom"

    static func storageKey(userId: String) -> String {
        "profile.avatar.\(userId)"
    }

    static func saved(for userId: String?) -> String? {
        guard let userId else { return nil }
        return UserDefaults.standard.string(forKey: storageKey(userId: userId))
    }

    static func save(_ assetName: String, for userId: String?) {
        guard let userId else { return }
        UserDefaults.standard.set(assetName, forKey: storageKey(userId: userId))
    }

    static func isAssetName(_ value: String) -> Bool {
        value.hasPrefix("Avatar_")
    }

    static func isCustom(_ value: String?) -> Bool {
        value == customToken
    }

    static func hasRenderableAvatar(_ value: String?) -> Bool {
        guard let value else { return false }
        return isAssetName(value) || isCustom(value)
    }

    // MARK: Custom photo file

    static func customImageURL(for userId: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(userId).jpg")
    }

    @discardableResult
    static func saveCustomImage(_ image: UIImage, for userId: String?) -> Bool {
        let id = userId ?? "pending"
        let prepared = squareCropped(image, maxSide: 720)
        guard let data = prepared.jpegData(compressionQuality: 0.88) else { return false }
        do {
            try data.write(to: customImageURL(for: id), options: .atomic)
            if let userId {
                save(customToken, for: userId)
            }
            return true
        } catch {
            return false
        }
    }

    /// Move a photo taken before login/session into the real user slot.
    static func promotePendingCustom(to userId: String) {
        let pending = customImageURL(for: "pending")
        guard FileManager.default.fileExists(atPath: pending.path) else { return }
        let dest = customImageURL(for: userId)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: pending, to: dest)
        save(customToken, for: userId)
    }

    static func loadCustomImage(for userId: String?) -> UIImage? {
        let candidates = [userId, "pending"].compactMap { $0 }
        for id in candidates {
            let url = customImageURL(for: id)
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    /// Persist catalog pick or finalize a custom photo for `userId`.
    static func persistSelection(_ selection: String, for userId: String?) {
        guard let userId else { return }
        if isCustom(selection) {
            promotePendingCustom(to: userId)
            save(customToken, for: userId)
        } else {
            save(selection, for: userId)
        }
    }

    /// Center-crop to square, then downscale for storage.
    static func squareCropped(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let crop = CGRect(origin: origin, size: CGSize(width: side, height: side))
        guard let cg = image.cgImage?.cropping(to: crop * image.scale) else {
            return resized(image, maxSide: maxSide)
        }
        let cropped = UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        return resized(cropped, maxSide: maxSide)
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private extension CGRect {
    static func * (rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        )
    }
}

/// Renders catalog avatar, custom photo, initials, or SF Symbol.
struct TTAvatarImage: View {
    var assetName: String?
    var userId: String? = nil
    var systemName: String? = nil
    var initials: String = "?"
    var size: CGFloat = 120

    var body: some View {
        Group {
            if let assetName, TTAvatarCatalog.isCustom(assetName),
               let custom = TTAvatarCatalog.loadCustomImage(for: userId) {
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
            } else if let assetName, TTAvatarCatalog.isAssetName(assetName) {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(Color(white: 0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.94))
            } else {
                Text(initials.uppercased())
                    .font(TTFont.workSans(size * 0.36, weight: .bold))
                    .foregroundStyle(Color(white: 0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.94))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Shared “Choose your avatar” step — catalog grid + Gallery + Take photo.
struct AssessmentAvatarStep: View {
    @Binding var selection: String
    var userId: String? = nil
    var title: String = "Choose your avatar"
    var subtitle: String = "Pick a look, choose from gallery, or take a photo."

    @Namespace private var avatarNamespace
    @State private var didAppear = false
    @State private var heroPulse = false
    @State private var swapToken = 0
    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var customPreview: UIImage?
    @State private var isImporting = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private let orange = TTColor.actionOrange

    private var selectSpring: Animation {
        .spring(response: 0.45, dampingFraction: 0.68, blendDuration: 0.15)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 24)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 28)

            heroPreview
                .padding(.top, 20)

            photoSourceRow
                .padding(.horizontal, 24)
                .padding(.top, 18)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(TTAvatarCatalog.all.enumerated()), id: \.element) { index, name in
                        avatarCell(name, index: index)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if selection.isEmpty {
                selection = TTAvatarCatalog.default
            }
            if TTAvatarCatalog.isCustom(selection) {
                customPreview = TTAvatarCatalog.loadCustomImage(for: userId)
            } else if !TTAvatarCatalog.isAssetName(selection) {
                selection = TTAvatarCatalog.default
            }
            withAnimation(.easeOut(duration: 0.55)) {
                didAppear = true
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                heroPulse = true
            }
        }
        .onChange(of: libraryItem) { _, item in
            Task { await importLibraryItem(item) }
        }
        .onChange(of: cameraImage) { _, image in
            guard let image else { return }
            applyCustomPhoto(image)
            cameraImage = nil
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .sensoryFeedback(.selection, trigger: selection)
        .overlay {
            if isImporting {
                ProgressView()
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Photo sources

    private var photoSourceRow: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $libraryItem, matching: .images, photoLibrary: .shared()) {
                sourceChip(title: "Gallery", icon: .image1)
            }
            .buttonStyle(AvatarCellPressStyle())

            Button {
                showCamera = true
            } label: {
                sourceChip(title: "Take a photo", icon: .camera1)
            }
            .buttonStyle(AvatarCellPressStyle())
        }
    }

    private func sourceChip(title: String, icon: SandowIcon) -> some View {
        HStack(spacing: 8) {
            TTIcon(icon: icon, filled: true, size: 16)
            Text(title)
                .font(TTFont.workSans(14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(TTColor.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(Color(white: 0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Hero

    private var heroPreview: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orange.opacity(0.35), orange.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)
                .scaleEffect(heroPulse ? 1.08 : 0.92)
                .blur(radius: 6)

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [orange, orange.opacity(0.2), .white.opacity(0.7), orange],
                        center: .center
                    ),
                    lineWidth: 3.5
                )
                .frame(width: 136, height: 136)
                .rotationEffect(.degrees(heroPulse ? 18 : -8))
                .scaleEffect(heroPulse ? 1.03 : 0.98)

            Group {
                if TTAvatarCatalog.isCustom(selection), let customPreview {
                    Image(uiImage: customPreview)
                        .resizable()
                        .scaledToFill()
                } else if TTAvatarCatalog.isAssetName(selection) {
                    Image(selection)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(white: 0.92)
                }
            }
            .frame(width: 124, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .matchedGeometryEffect(id: selection, in: avatarNamespace, isSource: true)
            .shadow(color: orange.opacity(0.28), radius: 18, y: 10)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
            .id(swapToken)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.72).combined(with: .opacity),
                    removal: .scale(scale: 1.12).combined(with: .opacity)
                )
            )
        }
        .frame(height: 180)
        .animation(selectSpring, value: selection)
    }

    // MARK: - Grid cell

    private func avatarCell(_ name: String, index: Int) -> some View {
        let isSelected = selection == name
        let delay = Double(index) * 0.028

        return Button {
            guard selection != name else {
                withAnimation(selectSpring) { swapToken += 1 }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(selectSpring) {
                selection = name
                swapToken += 1
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(orange.opacity(0.55), lineWidth: 2)
                        )
                        .overlay {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(orange)
                                .symbolEffect(.bounce, value: swapToken)
                        }
                } else {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .matchedGeometryEffect(id: name, in: avatarNamespace, isSource: true)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.04), lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .scaleEffect(isSelected ? 0.94 : (didAppear ? 1 : 0.82))
            .opacity(didAppear ? (isSelected ? 0.95 : 1) : 0)
            .offset(y: didAppear ? 0 : 16)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.78).delay(didAppear ? 0 : delay),
                value: didAppear
            )
            .animation(selectSpring, value: selection)
        }
        .buttonStyle(AvatarCellPressStyle())
        .accessibilityLabel("Avatar \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Import

    @MainActor
    private func importLibraryItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isImporting = true
        defer { isImporting = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        applyCustomPhoto(image)
        libraryItem = nil
    }

    private func applyCustomPhoto(_ image: UIImage) {
        let prepared = TTAvatarCatalog.squareCropped(image, maxSide: 720)
        customPreview = prepared
        if let userId {
            _ = TTAvatarCatalog.saveCustomImage(prepared, for: userId)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(selectSpring) {
            selection = TTAvatarCatalog.customToken
            swapToken += 1
        }
    }
}

private struct AvatarCellPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview("Avatar Step") {
    struct Demo: View {
        @State private var selection = TTAvatarCatalog.default
        var body: some View {
            AssessmentAvatarStep(selection: $selection, userId: "preview")
                .background(Color.white)
        }
    }
    return Demo()
}
