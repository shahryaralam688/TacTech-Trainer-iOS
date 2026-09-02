import PhotosUI
import SwiftUI
import UIKit

struct FoodScannerView: View {
    @Environment(AppStore.self) private var store
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var result: FoodRecognitionResult?
    @State private var grams = 220.0
    @State private var isBusy = false
    @State private var saved = false
    @State private var showCamera = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TTScreenHeader(eyebrow: "AI estimate", title: "Food Scanner")
                preview
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        compact("Photo library", "photo")
                    }
                    Button {
                        showCamera = true
                    } label: {
                        compact("Camera", "camera")
                    }
                }
                if let result {
                    estimateCard(result)
                } else {
                    Text("Take or choose a meal photo. TacTech classifies it on-device and returns estimated calories and macros.")
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            .padding(20)
        }
        .ttScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
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

    private var preview: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 28))
                        .foregroundStyle(TTColor.brand)
                    Text("Meal photo")
                        .font(TTFont.heading(15))
                    Text(isBusy ? "Recognizing…" : "Nothing selected yet")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(TTColor.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: TTRadius.lg, style: .continuous))
    }

    private func estimateCard(_ result: FoodRecognitionResult) -> some View {
        let macros = scaled(result.food)
        return VStack(alignment: .leading, spacing: 12) {
            Text(result.food.name)
                .font(TTFont.title(22))
            Text("Matched \(result.label) · \(Int(result.confidence * 100))% confidence")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            Slider(value: $grams, in: 80...700, step: 10)
            Text("Portion \(Int(grams)) g")
                .font(TTFont.caption(13))
                .foregroundStyle(TTColor.inkMuted)
            HStack {
                macro("kcal", "\(macros.calories)", TTColor.calorie)
                macro("P", String(format: "%.0f", macros.protein), TTColor.protein)
                macro("C", String(format: "%.0f", macros.carbs), TTColor.carbs)
                macro("F", String(format: "%.0f", macros.fat), TTColor.fat)
            }
            Text("Nutrition values are estimates, not lab-accurate measurements.")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkSubtle)
            TTButton(title: saved ? "Saved" : "Save meal", icon: "checkmark") {
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
                        saved = true
                    } catch {
                        saved = false
                    }
                }
            }
        }
        .ttCard()
    }

    private func macro(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(TTFont.heading(16)).foregroundStyle(tint)
            Text(title).font(TTFont.caption(11)).foregroundStyle(TTColor.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func compact(_ title: String, _ icon: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title).font(TTFont.heading(14))
        }
        .foregroundStyle(TTColor.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(TTColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TTColor.line, lineWidth: 1)
        )
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
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
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

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
    }
}
