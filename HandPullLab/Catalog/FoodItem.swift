import Foundation

enum FoodCategory: String, CaseIterable, Identifiable {
    case all = "All", ramen = "Ramen", sushi = "Sushi", rolls = "Rolls", soups = "Soups"
    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .all: "🍽️"
        case .ramen: "🍜"
        case .sushi: "🍣"
        case .rolls: "🍱"
        case .soups: "🥣"
        }
    }
}

struct FoodItem: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let category: FoodCategory
    let price: Double
    let rating: String
    let description: String

    static let samples: [FoodItem] = [
        .init(id: "ichiraku", name: "Ichiraku Ramen", emoji: "🍜", category: .ramen, price: 15, rating: "4.5", description: "Пшеничная лапша, насыщенный бульон, яйцо и свежий зелёный лук."),
        .init(id: "philadelphia", name: "Philadelphia roll", emoji: "🍱", category: .rolls, price: 9.5, rating: "4.8", description: "Нежный лосось, сливочный сыр и огурец. Порция из восьми кусочков."),
        .init(id: "salmon", name: "Salmon sushi", emoji: "🍣", category: .sushi, price: 7, rating: "5.0", description: "Классические нигири с лососем на подушке риса."),
        .init(id: "miso", name: "Miso soup", emoji: "🥣", category: .soups, price: 4.5, rating: "4.3", description: "Лёгкий мисо-бульон с тофу, водорослями и луком."),
        .init(id: "spicy", name: "Spicy Ramen", emoji: "🍜", category: .ramen, price: 14, rating: "4.7", description: "Острый бульон с чили, лапша и хрустящие овощи."),
        .init(id: "california", name: "California roll", emoji: "🍱", category: .rolls, price: 10, rating: "4.6", description: "Авокадо, огурец и краб в рисовой оболочке с кунжутом."),
        .init(id: "shrimp", name: "Shrimp sushi", emoji: "🍤", category: .sushi, price: 8, rating: "4.8", description: "Креветка с нежным рисом и лёгкой цитрусовой заправкой."),
        .init(id: "pumpkin", name: "Pumpkin soup", emoji: "🥣", category: .soups, price: 6, rating: "4.7", description: "Кремовый суп из запечённой тыквы с семечками."),
        .init(id: "veggie", name: "Veggie Ramen", emoji: "🍜", category: .ramen, price: 12, rating: "4.9", description: "Овощной бульон, грибы, кукуруза и зелень."),
        .init(id: "avocado", name: "Avocado roll", emoji: "🥑", category: .rolls, price: 7.5, rating: "4.6", description: "Простой ролл с авокадо, рисом и нори."),
        .init(id: "tuna", name: "Tuna sushi", emoji: "🍣", category: .sushi, price: 8.5, rating: "4.9", description: "Нигири с тунцом. Подаётся с имбирём и васаби."),
        .init(id: "tomato", name: "Tomato soup", emoji: "🍅", category: .soups, price: 5.5, rating: "4.5", description: "Томатный суп с базиликом и поджаренным хлебом.")
    ]
}
