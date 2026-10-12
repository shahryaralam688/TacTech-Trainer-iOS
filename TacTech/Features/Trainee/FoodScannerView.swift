import PhotosUI
import SwiftUI
import UIKit

// MARK: - Food Scanner (Sandow / TacTech system design)

struct FoodScannerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var result: FoodRecognitionResult?
    @State private var grams = 220.0
    @State private var isBusy = false
    @State private var saved = false
    @State private var showCamera = false

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let orange = TTColor.actionOrange

    var body: some View {
        VStack(spacing: 0) {
            TTDarkPageHeader(title: "Food Scanner") {
                dismiss()
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("AI ESTIMATE")
                        .font(TTFont.caption(11))
                        .fontWeight(.bold)
                        .tracking(0.8)
                        .foregroundStyle(orange)

                    preview

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            actionChip(title: "Photo library", icon: .image1)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showCamera = true
                        } label: {
                            actionChip(title: "Camera", icon: .camera1)
                        }
                        .buttonStyle(.plain)
                    }

                    if let result {
                        estimateCard(result)
                    } else {
                        Text("Take or choose a meal photo. TacTech classifies it on-device and returns estimated calories and macros.")
                            .font(TTFont.body(14))
                            .foregroundStyle(TTColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
        }
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .onChange(of: pickerItem) { _, item in
            Task { await load(item) }
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(image: $image)
                .ignoresSafeArea()
        }
        .onChange(of: image) { _, newValue in
            if let newValue { Task { await classify(newValue) } }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: TTCardTokens.thumbCorner, style: .continuous)
                            .fill(orange.opacity(0.12))
                            .frame(width: 56, height: 56)
                        TTIcon(icon: .scan1, filled: true, size: 24)
                            .foregroundStyle(orange)
                    }
                    Text("Meal photo")
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text(isBusy ? "Recognizing…" : "Nothing selected yet")
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
        .clipped()
    }

    // MARK: - Estimate

    private func estimateCard(_ result: FoodRecognitionResult) -> some View {
        let macros = scaled(result.food)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.food.name)
                    .font(TTFont.workSans(20, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text("Matched \(result.label) · \(Int(result.confidence * 100))% confidence")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Portion")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(TTColor.inkMuted)
                    Spacer()
                    Text("\(Int(grams)) g")
                        .font(TTFont.workSans(13, weight: .bold))
                        .foregroundStyle(orange)
                }
                Slider(value: $grams, in: 80...700, step: 10)
                    .tint(orange)
            }

            HStack(spacing: 8) {
                macro("kcal", "\(macros.calories)", TTColor.calorie)
                macro("P", String(format: "%.0f", macros.protein), TTColor.protein)
                macro("C", String(format: "%.0f", macros.carbs), TTColor.carbs)
                macro("F", String(format: "%.0f", macros.fat), TTColor.fat)
            }

            Text("Nutrition values are estimates, not lab-accurate measurements.")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkSubtle)

            Button {
                saveMeal(result, macros: macros)
            } label: {
                HStack(spacing: 8) {
                    TTIcon(icon: saved ? .check : .forkKnife, filled: true, size: 16)
                    Text(saved ? "Saved" : "Save meal")
                        .font(TTFont.workSans(15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(saved ? TTColor.success : orange)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(saved)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }

    private func macro(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(TTFont.workSans(16, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func actionChip(title: String, icon: SandowIcon) -> some View {
        HStack(spacing: 8) {
            TTIcon(icon: icon, filled: true, size: 16)
                .foregroundStyle(orange)
            Text(title)
                .font(TTFont.workSans(14, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func saveMeal(_ result: FoodRecognitionResult, macros: MacroEstimate) {
        guard let trainee = store.currentTrainee else { return }
        Task {
            do {
                try await store.saveMeal(
                    Meal(
                        id: UUID().uuidString,
                        traineeId: trainee.id,
                        name: result.food.name,
                        eatenAt: .now,
                        portionGrams: grams,
                        macros: macros,
                        source: "scan",
                        isEstimate: true
                    )
                )
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    saved = true
                }
            } catch {
                saved = false
            }
        }
    }

    private func scaled(_ food: FoodKnowledge) -> MacroEstimate {
        let factor = grams / 100
        return MacroEstimate(
            calories: Int(Double(food.per100g.calories) * factor),
            protein: food.per100g.protein * factor,
            carbs: food.per100g.carbs * factor,
            fat: food.per100g.fat * factor
        )
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        self.image = image
        await classify(image)
    }

    private func classify(_ image: UIImage) async {
        isBusy = true
        saved = false
        result = await FoodRecognizer.recognize(image: image, catalog: store.foodCatalog)
        isBusy = false
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
    }
}

#Preview("Food Scanner") {
    NavigationStack {
        FoodScannerView()
            .ttPreviewTrainee()
    }
}
