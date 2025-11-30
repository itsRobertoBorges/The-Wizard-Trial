//
//  PlayerInventory.swift
//  The Wizard's Trial
//

import Foundation
import Combine

final class PlayerInventory: ObservableObject {

    static let shared = PlayerInventory()

    private let defaults = UserDefaults.standard
    private let coinsKey = "playerCoins"
    private let slotsKey = "playerSlots"
    private let quickSlotsKey = "playerQuickSlots"

    // MARK: - Published

    @Published private(set) var coins: Int {
        didSet { defaults.set(coins, forKey: coinsKey) }
    }

    @Published var slots: [ShopItem?] {
        didSet { saveInventory() }
    }

    @Published var quickSlots: [ShopItem?] {
        didSet { saveQuickSlots() }
    }

    // MARK: Init

    init() {
        self.coins = defaults.integer(forKey: coinsKey)

        // Load inventory slots
        if let arr = defaults.array(forKey: slotsKey) as? [String] {
            self.slots = arr.map { str in
                if str == "null" { return nil }
                if let data = Data(base64Encoded: str) {
                    return try? JSONDecoder().decode(ShopItem.self, from: data)
                }
                return nil
            }
        } else {
            self.slots = Array(repeating: nil, count: 16)
        }

        // Load quick slots
        if let arr = defaults.array(forKey: quickSlotsKey) as? [String] {
            self.quickSlots = arr.map { str in
                if str == "null" { return nil }
                if let data = Data(base64Encoded: str) {
                    return try? JSONDecoder().decode(ShopItem.self, from: data)
                }
                return nil
            }
        } else {
            self.quickSlots = Array(repeating: nil, count: 3)
        }
    }

    // MARK: Saving

    private func saveInventory() {
        let encoded = slots.map { item -> String in
            if let item = item,
               let data = try? JSONEncoder().encode(item) {
                return data.base64EncodedString()
            }
            return "null"
        }
        defaults.set(encoded, forKey: slotsKey)
    }

    private func saveQuickSlots() {
        let encoded = quickSlots.map { item -> String in
            if let item = item,
               let data = try? JSONEncoder().encode(item) {
                return data.base64EncodedString()
            }
            return "null"
        }
        defaults.set(encoded, forKey: quickSlotsKey)
    }

    // MARK: Coins

    func addCoins(_ amount: Int) { coins += amount }

    // MARK: Buy

    func tryBuy(_ item: ShopItem) -> Bool {
        guard coins >= item.price else { return false }
        guard let index = slots.firstIndex(where: { $0 == nil }) else { return false }

        coins -= item.price
        slots[index] = item
        return true
    }

    // MARK: Remove ONE item

    func destroyOne(_ item: ShopItem) {
        if let index = slots.firstIndex(where: { $0?.id == item.id }) {
            slots[index] = nil
            return
        }
        if let index = quickSlots.firstIndex(where: { $0?.id == item.id }) {
            quickSlots[index] = nil
            return
        }
    }

    // MARK: Equip

    func equip(_ item: ShopItem, to slotIndex: Int) {
        guard quickSlots.indices.contains(slotIndex) else { return }

        if let invIndex = slots.firstIndex(where: { $0?.id == item.id }) {
            let previous = quickSlots[slotIndex]
            quickSlots[slotIndex] = item
            slots[invIndex] = previous
            return
        }

        quickSlots[slotIndex] = item
    }

    // MARK: Swap

    func swapSlots(_ a: Int, _ b: Int) {
        guard slots.indices.contains(a), slots.indices.contains(b), a != b else { return }
        slots.swapAt(a, b)
    }
}
