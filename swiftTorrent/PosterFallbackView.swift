import SwiftUI

struct PosterFallbackView: View {
    let symbol: String
    let title: String?
    let cornerRadius: CGFloat

    init(symbol: String, title: String? = nil, cornerRadius: CGFloat = 10) {
        self.symbol = symbol
        self.title = title
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)

            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
        }
    }
}
