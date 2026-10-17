import SwiftUI

enum CatalogStyle {
    static let background = Color(red: 0.975, green: 0.972, blue: 0.974)
}

struct FoodCardView: View {
    let item: FoodItem
    let isExpanded: Bool
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? .red : .primary)
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("\(isFavorite ? "Убрать из избранного" : "В избранное"): \(item.name)")
            .accessibilityValue(isFavorite ? "В избранном" : "Не в избранном")
            .accessibilityIdentifier("favorite.\(item.id)")

            Button(action: open) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.emoji)
                        .font(.system(size: 68))
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .accessibilityHidden(true)
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isExpanded {
                        Text(item.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            price
                            Spacer(minLength: 4)
                            rating
                        }
                        VStack(alignment: .leading, spacing: 5) { price; rating }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(item.name), \(item.price.formatted(.currency(code: "USD"))), рейтинг \(item.rating). Подробнее")
            .accessibilityIdentifier("food.\(item.id)")
        }
        .buttonStyle(.plain)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var price: some View { Text(item.price, format: .currency(code: "USD")).font(.subheadline).foregroundStyle(.primary) }
    private var rating: some View {
        Label(item.rating, systemImage: "star.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
