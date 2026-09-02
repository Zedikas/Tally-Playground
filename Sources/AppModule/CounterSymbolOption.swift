import Foundation

struct CounterSymbolOption: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String

    static let all: [CounterSymbolOption] = [
        .init(id: "counter", title: "Counter", symbol: "number.square.fill"),
        .init(id: "completed", title: "Completed", symbol: "checkmark.seal.fill"),
        .init(id: "water", title: "Water", symbol: "drop.fill"),
        .init(id: "streak", title: "Streak", symbol: "flame.fill"),
        .init(id: "energy", title: "Energy", symbol: "bolt.fill"),
        .init(id: "reading", title: "Reading", symbol: "book.fill"),
        .init(id: "shopping", title: "Shopping", symbol: "cart.fill"),
        .init(id: "gaming", title: "Gaming", symbol: "gamecontroller.fill"),
        .init(id: "workout", title: "Workout", symbol: "figure.strengthtraining.traditional"),
        .init(id: "favorite", title: "Favorite", symbol: "star.fill"),
        .init(id: "inventory", title: "Inventory", symbol: "shippingbox.fill"),
        .init(id: "calendar", title: "Calendar", symbol: "calendar"),
        .init(id: "achievement", title: "Achievement", symbol: "trophy.fill"),
        .init(id: "timer", title: "Timer", symbol: "timer"),
        .init(id: "checklist", title: "Checklist", symbol: "checklist"),
        .init(id: "money", title: "Money", symbol: "dollarsign.circle.fill"),
        .init(id: "medication", title: "Medication", symbol: "pills.fill"),
        .init(id: "drinks", title: "Drinks", symbol: "cup.and.saucer.fill"),
        .init(id: "steps", title: "Steps", symbol: "figure.walk"),
        .init(id: "focus", title: "Focus", symbol: "scope"),
        .init(id: "habit", title: "Habit", symbol: "repeat.circle.fill"),
        .init(id: "health", title: "Health", symbol: "heart.fill"),
        .init(id: "work", title: "Work", symbol: "briefcase.fill"),
        .init(id: "study", title: "Study", symbol: "graduationcap.fill")
    ]

    static func title(for symbol: String) -> String {
        all.first(where: { $0.symbol == symbol })?.title ?? "Custom"
    }
}
