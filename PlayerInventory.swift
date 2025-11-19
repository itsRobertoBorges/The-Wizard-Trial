//
//  PlayerInventory.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2025-11-17.
//

//
//  PlayerInventory.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2025-11-17.
//

import Foundation
import Combine

/// Global, persistent player inventory.
final class PlayerInventory: ObservableObject {
    static let shared = PlayerInventory()

    // MARK: - Constants

    private let storageKey = "WT_PlayerInventory_v1"
    private let slotCount = 16
    private let quickSlotCount = 3

    // MARK: - Published state

    /// Permanent coins (survive app quits)
    @Published private(set) var coins: Int {
        didSet { save() }
    }

    /// Main inventory slots (16 items, persist by ID)
    @Published private(set) var slots: [ShopItem?] {
        didSet { save() }
    }

    /// Quick slots (3 items, persist by ID)
    @Published private(set) var quickSlots: [ShopItem?] {
        didSet { save() }
    }

    // MARK: - Persistence model

    private struct Persisted: Codable {
        var coins: Int
        var slotIDs: [String?]
        var quickSlotIDs: [String?]
    }

    // MARK: - Init

    init() {
        // Try to load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {

            self.coins = decoded.coins
            self.slots = Self.items(fromIDs: decoded.slotIDs)
            self.quickSlots = Self.items(fromIDs: decoded.quickSlotIDs, count: quickSlotCount)
            normalizeCounts()

        } else {
            // First run / no save yet
            self.coins = 0
            self.slots = Array(repeating: nil, count: slotCount)
            self.quickSlots = Array(repeating: nil, count: quickSlotCount)
        }
    }

    // MARK: - Helpers for mapping IDs <-> ShopItem

    private static func items(fromIDs ids: [String?], count: Int? = nil) -> [ShopItem?] {
        let mapped: [ShopItem?] = ids.map { id in
            guard let id else { return nil }
            return shopItems.first(where: { $0.id == id })
        }

        guard let count = count else { return mapped }

        if mapped.count >= count {
            return Array(mapped.prefix(count))
        } else {
            return mapped + Array(repeating: nil, count: count - mapped.count)
        }
    }

    /// Ensure slots / quickSlots always have the right lengths.
    private func normalizeCounts() {
        if slots.count != slotCount {
            if slots.count > slotCount {
                slots = Array(slots.prefix(slotCount))
            } else {
                slots += Array(repeating: nil, count: slotCount - slots.count)
            }
        }

        if quickSlots.count != quickSlotCount {
            if quickSlots.count > quickSlotCount {
                quickSlots = Array(quickSlots.prefix(quickSlotCount))
            } else {
                quickSlots += Array(repeating: nil, count: quickSlotCount - quickSlots.count)
            }
        }
    }

    // MARK: - Save

    private func save() {
        let payload = Persisted(
            coins: coins,
            slotIDs: slots.map { $0?.id },
            quickSlotIDs: quickSlots.map { $0?.id }
        )

        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Coins

    func addCoins(_ amount: Int) {
        guard amount > 0 else { return }
        coins += amount
    }

    /// Attempt to buy an item (only succeeds if you can afford *and* have space).
    @discardableResult
    func tryBuy(_ item: ShopItem) -> Bool {
        guard coins >= item.price else { return false }
        // Only charge if we can actually store the item
        guard addItem(item) else { return false }
        coins -= item.price
        return true
    }

    // MARK: - Inventory items

    /// Add item to the first empty slot. Returns false if inventory is full.
    @discardableResult
    func addItem(_ item: ShopItem) -> Bool {
        if let idx = slots.firstIndex(where: { $0 == nil }) {
            slots[idx] = item
            return true
        }
        return false
    }

    /// Destroy all copies of this item in main inventory and quick slots.
    func destroy(_ item: ShopItem) {
        // Remove from main slots
        for i in slots.indices {
            if slots[i]?.id == item.id {
                slots[i] = nil
            }
        }
        // Remove from quick slots
        for i in quickSlots.indices {
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
        guard quickSlots.indices.contains(slotIndex) else { return }

        // Put item in the chosen quick slot
        quickSlots[slotIndex] = item

        // Remove ONE copy of this item from the main inventory slots
        if let index = slots.firstIndex(where: { $0?.id == item.id }) {
            slots[index] = nil
        }
    }

}
