import SwiftUI

enum WorldID: String {
    case witheringTree
    case blackrockValley
    case drownedSanctum
    case lightningTemple
    case hollowGarden
    case towerOfBabel
}

private enum Route { case menu, intro, worldSelect, loading, game, shop }

struct RootView: View {
    @State private var route: Route = .menu
    @State private var fadeOut = false
    @State private var selectedWorld: WorldID = .witheringTree

    var body: some View {
        ZStack {
            switch route {
            case .menu:
                MainMenuView(
                    onPlay: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            route = .intro
                        }
                    },
                    onShop: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            route = .shop
                        }
                    }
                )
                .transition(.opacity)

            case .intro:
                IntroView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        route = .worldSelect
                    }
                }
                .transition(.opacity)

            case .worldSelect:
                WorldSelectionView(
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            route = .menu
                        }
                    },
                    onSelectWorld: { world in      // 👈 world: WorldID
                        selectedWorld = world      // remember which world
                        withAnimation(.easeInOut(duration: 0.25)) {
                            route = .loading
                        }
                    }
                )
                .transition(.opacity)

            case .loading:
                LoadingScreenView(
                    duration: 4.0,
                    mode: .classic(bg: "loadingscreen", text: "loadingscreentext")
                ) {
                    withAnimation(.easeInOut(duration: 0.35)) { fadeOut = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        fadeOut = false
                        withAnimation(.easeInOut(duration: 0.25)) {
                            route = .game
                        }
                    }
                }
                .overlay(
                    Rectangle()
                        .fill(Color.black)
                        .opacity(fadeOut ? 1.0 : 0.0)
                        .ignoresSafeArea()
                )
                .transition(.opacity)

            case .game:
                ContentView(
                    world: selectedWorld,
                    onExitToMenu: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            route = .menu
                        }
                    }
                )
                .transition(.opacity)


            case .shop:
                ShopView(onExit: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        route = .menu
                    }
                })
                .transition(.opacity)
            }
        }
    }
}
