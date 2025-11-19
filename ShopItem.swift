import Foundation

/// A single shop / inventory item.
/// `id` is a stable string so we can save / reload it easily.
struct ShopItem: Identifiable, Codable, Hashable {
    let id: String        // unique key, e.g. "healthpotion"
    let imageName: String
    let name: String
    let price: Int
    let desc: String
}

/// Global list of all items available in the shop.
let shopItems: [ShopItem] = [
    ShopItem(
        id: "healthpotion",
        imageName: "healthpotion",
        name: "Health Potion",
        price: 20,
        desc: "A staple in any wizard’s pack. Restores a modest portion of vitality."
    ),
    ShopItem(
        id: "manacrystal",
        imageName: "manacrystal",
        name: "Mana Crystal",
        price: 30,
        desc: "Crackling with latent arcana. Restores your inner reserves of power."
    ),
    ShopItem(
        id: "manashield",
        imageName: "manashield",
        name: "Mana Shield",
        price: 25,
        desc: "A ward of pure ether. Absorbs mana instead of health."
    ),
    ShopItem(
        id: "fairydust",
        imageName: "fairydust",
        name: "Fairy Dust",
        price: 40,
        desc: "Bottled wonder from ancient groves. Fills your health bar."
    ),
    ShopItem(
        id: "lightningshield",
        imageName: "lightningshield",
        name: "Lightning Shield",
        price: 60,
        desc: "A stormbound aegis. Zaps nearby foes that dare approach."
    ),
    ShopItem(
        id: "rapidwand",
        imageName: "rapidwand",
        name: "Rapid Wand",
        price: 55,
        desc: "Light as a reed; swift as thought. Increases casting speed."
    ),
    ShopItem(
        id: "blizzardspell",
        imageName: "blizzardspell",
        name: "Blizzard Spell",
        price: 45,
        desc: "Invoke the Northwind. Unleash freezing shards upon your enemies."
    ),
    ShopItem(
        id: "fireballspell",
        imageName: "fireballspell",
        name: "Fire Ball Spell",
        price: 35,
        desc: "Old faithful of battlemages. Hurls a blazing orb at your target. Bounces 3 times"
    ),
    ShopItem(
        id: "iceblock",
        imageName: "iceblock",
        name: "Ice Block",
        price: 35,
        desc: "Become encased in frost to shrug off danger—for a moment."
    ),
    ShopItem(
        id: "revive",
        imageName: "revive",
        name: "Revive",
        price: 200,
        desc: "An angelic boon. Pulls you back from the brink once per run."
    )
]
