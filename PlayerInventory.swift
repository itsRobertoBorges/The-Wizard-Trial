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
            // You can persist coins here later if you want
        }
    }

    // 16 inventory slots
    @Published var slots: [ShopItem?]

    // 3 quick slots
    @Published var quickSlots: [ShopItem?]

    init() {
        self.coins = 0
        self.slots = Array(repeating: nil, count: 16)
        self.quickSlots = Array(repeating: nil, count: 3)
    }

    // MARK: - Coins

    func addCoins(_ amount: Int) {
        coins += amount
    }
    
    // MARK: - Shop / buying logic

    /// Attempts to buy an item:
    /// - returns true if purchase succeeded (coins deducted + item added)
    /// - returns false if not enough coins or no free inventory slot.
    func tryBuy(_ item: ShopItem) -> Bool {
        // Not enough coins
        guard coins >= item.price else {
            return false
        }

        // Find an empty inventory slot
        guard let emptyIndex = slots.firstIndex(where: { $0 == nil }) else {
            // No space in inventory
            return false
        }

        // Perform purchase
        coins -= item.price
        slots[emptyIndex] = item
        return true
    }


    // MARK: - Inventory add/remove

    func add(_ item: ShopItem) -> Bool {
        if let index = slots.firstIndex(where: { $0 == nil }) {
            slots[index] = item
            return true
        }
        return false
    }

    func destroy(_ item: ShopItem) {
        // Remove ALL copies (used by consume, if you still want that behavior)
        for i in slots.indices {
            if slots[i]?.id == item.id {
                slots[i] = nil
            }
        }

        for i in quickSlots.indices {
            if quickSlots[i]?.id == item.id {
                quickSlots[i] = nil
            }
        }
    }

    func consume(_ item: ShopItem) {
        destroy(item)
    }

    // MARK: - NEW: destroy ONE copy from inventory grid

    func destroyOneInInventory(_ item: ShopItem) {
        if let index = slots.firstIndex(where: { $0?.id == item.id }) {
            slots[index] = nil
        }
    }

    // MARK: - Quick slots

    func equip(_ item: ShopItem, to slotIndex: Int) {
        guard quickSlots.indices.contains(slotIndex) else { return }

        // Find the item in inventory slots
        guard let invIndex = slots.firstIndex(where: { $0?.id == item.id }) else {
            quickSlots[slotIndex] = item
            return
        }

        // Swap with what was in the quick slot
        let previousQuickItem = quickSlots[slotIndex]
        quickSlots[slotIndex] = item
        slots[invIndex] = previousQuickItem
    }

    // MARK: - NEW: swap inventory slots (drag & drop)

    func swapSlots(_ a: Int, _ b: Int) {
        guard slots.indices.contains(a),
              slots.indices.contains(b),
              a != b else { return }

        let temp = slots[a]
        slots[a] = slots[b]
        slots[b] = temp
    }
}
