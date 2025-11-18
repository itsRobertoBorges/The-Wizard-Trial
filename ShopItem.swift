import Foundation

struct ShopItem: Identifiable, Equatable, Codable {
    let id: UUID
    let imageName: String
    let name: String
    let price: Int
    let desc: String

    init(id: UUID = UUID(), imageName: String, name: String, price: Int, desc: String) {
        self.id = id
        self.imageName = imageName
        self.name = name
        self.price = price
        self.desc = desc
    }
}
