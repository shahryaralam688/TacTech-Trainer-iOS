import UIKit
import Vision

struct FoodRecognitionResult {
    var label: String
    var confidence: Double
    var food: FoodKnowledge
}

enum FoodRecognizer {
    static func recognize(image: UIImage, catalog: [FoodKnowledge]) async -> FoodRecognitionResult? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, _ in
                let observations = (request.results as? [VNClassificationObservation]) ?? []
                let match = observations.compactMap { observation -> FoodRecognitionResult? in
                    guard let food = catalog.first(where: { item in
                        item.keywords.contains { observation.identifier.lowercased().contains($0) }
                            || observation.identifier.lowercased().contains(item.name.lowercased())
                    }) else { return nil }
                    return FoodRecognitionResult(label: observation.identifier, confidence: Double(observation.confidence), food: food)
                }.max(by: { $0.confidence < $1.confidence })

                if let match {
                    continuation.resume(returning: match)
                    return
                }

                if let top = observations.first {
                    let fallback = catalog.first { top.identifier.lowercased().contains($0.keywords.first ?? "zzz") } ?? catalog[0]
                    continuation.resume(
                        returning: FoodRecognitionResult(
                            label: top.identifier,
                            confidence: Double(top.confidence),
                            food: fallback
                        )
                    )
                } else {
                    continuation.resume(returning: nil)
                }
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
