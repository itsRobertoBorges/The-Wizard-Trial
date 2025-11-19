//
//  PlayerInventory.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2025-11-17.
//

import Foundation
import Combine

final class PlayerInventory: ObservableObject {
    static let shared = PlayerInventory()

    // Permanent coins
    @Published private(set) var coins: Int {
        didSet {
            UserDefaults.standard.set(coins, forKey: "WT_totalCoins")
        }
    }

    // 16 inventory slots
    @Published var slots: [ShopItem?]

    // 3 quick slots
    @Published var quickSlots: [ShopItem?]

    private init() {
        self.coins = UserDefaults.standard.integer(forKey: "WT_totalCoins")
        self.slots = Array(repeating: nil, count: 16)
        self.quickSlots = Array(repeating: nil, count: 3)
    }

    // MARK: - Coins

    func addCoins(_ amount: Int) {
        guard amount > 0 else { return }
        coins += amount
    }

    func tryBuy(_ item: ShopItem) -> Bool {
        guard coins >= item.price else { return false }
        coins -= item.price
        addItem(item)
        return true
    }

    // MARK: - Inventory items

    func addItem(_ item: ShopItem) {
        if let emptyIndex = slots.firstIndex(where: { $0 == nil }) {
            slots[emptyIndex] = item
        } else {
            // Inventory full – for now, silently ignore
            print("⚠️ Inventory full, could not add \(item.name)")
        }
    }

    func destroy(_ item: ShopItem) {
        // Remove from main slots
        if let idx = slots.firstIndex(where: { $0?.id == item.id }) {
            slots[idx] = nil
        }

        // Also unequip from quick slots if present
        for i in 0..<quickSlots.count {
            if quickSlots[i]?.id == item.id {
                quickSlots[i] = nil
            }
        }
    }

    func consume(_ item: ShopItem) {
        destroy(item)
    }

    // MARK: - Quick slots

    func equip(_ item: ShopItem, to slotIndex: Int) {
        guard (0..<quickSlots.count).contains(slotIndex) else { return }
        quickSlots[slotIndex] = item
    }
}
