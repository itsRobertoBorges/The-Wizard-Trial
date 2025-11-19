import SwiftUI

@main
struct Veggie_DodgerApp: App {
    @StateObject private var inventory = PlayerInventory.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(inventory)
                .environment(\.font, Font.pixel(size: 14))
        }
    }
}
