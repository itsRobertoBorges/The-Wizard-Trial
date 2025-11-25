import Foundation

final class SaveManager {
    static let shared = SaveManager()
    private let defaults = UserDefaults.standard

    private init() {}

    // ===== COINS =====
    private let coinsKey = "playerCoins"

    func saveCoins(_ coins: Int) {
        defaults.set(coins, forKey: coinsKey)
    }

    func loadCoins() -> Int {
        defaults.integer(forKey: coinsKey)
    }

    // ===== INVENTORY =====
    private let inventoryKey = "playerInventory"

    func saveInventory(_ items: [String: Int]) {
        defaults.set(items, forKey: inventoryKey)
    }

    func loadInventory() -> [String: Int] {
        defaults.dictionary(forKey: inventoryKey) as? [String: Int] ?? [:]
    }
}
