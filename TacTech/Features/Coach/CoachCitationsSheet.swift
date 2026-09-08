import SwiftUI

struct CoachCitationsSheet: View {
    let citations: [CoachCitation]
    @Environment(\.dismiss) private var dismiss

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(citations) { cite in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(cite.sourceType.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(TTFont.workSans(13, weight: .bold))
                                    .foregroundStyle(orange)
                                Spacer()
                                Text(String(format: "%.0f%%", cite.score * 100))
                                    .font(TTFont.workSans(12, weight: .semibold))
                                    .foregroundStyle(muted)
                            }
                            Text(cite.content)
                                .font(TTFont.workSans(14, weight: .medium))
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(white: 0.97))
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(orange)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
