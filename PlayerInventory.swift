//
//  PlayerInventory.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2025-11-17.
//

import Foundation
import Combine

/// Global player inventory: permanent coins + items.
final class PlayerInventory: ObservableObject {

    private static let coinsKey = "WT_totalCoins"
    private static let itemsKey = "WT_items"

    /// Permanent coins (persists across runs & app restarts)
    @Published var coins: Int {
        didSet {
            UserDefaults.standard.set(coins, forKey: Self.coinsKey)
        }
    }

    /// Items owned (now also persisted)
    @Published var items: [ShopItem] {
        didSet {
            saveItems()
        }
    }

    init() {
        // Load coins from UserDefaults (0 if none saved yet)
        let storedCoins = UserDefaults.standard.integer(forKey: Self.coinsKey)
        self.coins = storedCoins

        // Load items from UserDefaults
        self.items = PlayerInventory.loadItems()
    }

    // MARK: - Persistence

    private static func loadItems() -> [ShopItem] {
        guard let data = UserDefaults.standard.data(forKey: itemsKey) else {
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([ShopItem].self, from: data)
            return decoded
        } catch {
            print("❌ Failed to decode saved items:", error)
            return []
        }
    }

    private func saveItems() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: Self.itemsKey)
        } catch {
            print("❌ Failed to encode items:", error)
        }
    }

    // MARK: - API

    /// Adds coins permanently
    func addCoins(_ amount: Int) {
        guard amount > 0 else { return }
        coins += amount
        // didSet already saves to UserDefaults
    }

    /// Try to buy an item; returns true if purchase succeeded
    @discardableResult
    func tryBuy(_ item: ShopItem) -> Bool {
        guard coins >= item.price else {
            return false
        }
        coins -= item.price
        items.append(item)   // triggers saveItems()
        return true
    }
}
