import SwiftUI
import AVFoundation

// ✅ Use your asset names (lowercase, no spaces)
private let shopItems: [ShopItem] = [
    .init(imageName: "healthpotion",    name: "Health Potion",    price: 20, desc: "A staple in any wizard’s pack. Restores a modest portion of vitality."),
    .init(imageName: "manacrystal",     name: "Mana Crystal",     price: 30, desc: "Crackling with latent arcana. Restores your inner reserves of power."),
    .init(imageName: "manashield",      name: "Mana Shield",      price: 25, desc: "A ward of pure ether. Absorbs minor harm before it reaches you."),
    .init(imageName: "fairydust",       name: "Fairy Dust",       price: 40, desc: "Bottled wonder from ancient groves. Enhances agility for a short time."),
    .init(imageName: "lightningshield", name: "Lightning Shield", price: 60, desc: "A stormbound aegis. Zaps nearby foes that dare approach."),
    .init(imageName: "rapidwand",       name: "Rapid Wand",       price: 55, desc: "Light as a reed; swift as thought. Increases casting speed."),
    .init(imageName: "blizzardspell",   name: "Blizzard Spell",   price: 45, desc: "Invoke the Northwind. Unleash freezing shards upon your enemies."),
    .init(imageName: "fireballspell",   name: "Fire Ball Spell",  price: 35, desc: "Old faithful of battlemages. Hurls a blazing orb at your target."),
    .init(imageName: "iceblock",        name: "Ice Block",        price: 35, desc: "Become encased in frost to shrug off danger—for a moment."),
    .init(imageName: "revive",          name: "Revive",           price: 75, desc: "An angelic boon. Pulls you back from the brink once per run.")
]

// MARK: - ShopView

struct ShopView: View {
    let onExit: () -> Void

    @EnvironmentObject var inventory: PlayerInventory   // ⬅️ shared inventory

    @State private var bgmPlayer: AVAudioPlayer?
    @State private var flicker: Double = 1.0
    @State private var parallaxOffset: CGFloat = 0
    @State private var showItems = false

    // Modal state
    @State private var selectedItem: ShopItem? = nil
    @State private var showingDetail = false

    private let chatLine = "Welcome, traveler! Spend your hard-earned coins on powerful relics."

    var body: some View {
        ZStack {
            // ===== Background =====
            GeometryReader { geo in
                Image("shopimage")
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.25)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .clipped()
                    .ignoresSafeArea()

                // ===== HUD =====
                VStack(spacing: 12) {
                    // Back button (hanging sign image)
                    HStack {
                        Button {
                            stopMusic()
                            onExit()
                        } label: {
                            Image("backbutton") // your oakwood hanging sign with left arrow
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 180)
                                .contentShape(Rectangle())
                                .padding(.leading, 16)
                                .padding(.top, -8)
                                .ignoresSafeArea(edges: .top)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // 🔹 Total coins display (top-right)
                        HStack(spacing: 6) {
                            Image(systemName: "circle.grid.3x3.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)

                            Text("\(inventory.coins)")
                                .font(.custom("PressStart2P-Regular", size: 12))
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .padding(.trailing, 16)
                        .padding(.top, 4)
                    }
                    .padding(.top, 44)
                    .zIndex(3)

                    // Chat box
                    HStack {
                        TypewriterText(
                            text: chatLine,
                            characterDelay: 0.04,
                            font: .custom("PressStart2P-Regular", size: 14),
                            onTypingStart: { duckBGM(true) },
                            onTypingEnd: {
                                duckBGM(false)
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                    showItems = true
                                }
                            }
                        )
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.65))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 2)
                                )
                        )
                        .shadow(color: .black.opacity(0.7), radius: 6, x: 0, y: 3)
                        .offset(y: 50)

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 16)
                    .zIndex(2)

                    Spacer()
                }

                // ===== Bottom gallery =====
                if showItems {
                    let galleryHeight = min(220, geo.size.height * 0.28)
                    bottomGallery(width: geo.size.width, height: galleryHeight)
                        .frame(width: geo.size.width, height: galleryHeight)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 10)
                        .zIndex(1)
                }
            }

            // ===== Item Detail Overlay =====
            if showingDetail, let item = selectedItem {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismissDetail() }

                ItemDetailView(
                    item: item,
                    onClose: { dismissDetail() }, inventory: _inventory
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(3)
            }
        }
        .onAppear { startAnimations(); playMusic() }
        .onDisappear { stopMusic() }
    }

    // MARK: - Bottom Gallery

    private func bottomGallery(width: CGFloat, height: CGFloat) -> some View {
        let horizontalPadding: CGFloat = 16
        let spacing: CGFloat = 10
        let available = width - (horizontalPadding * 2) - (spacing * 2)
        let cardWidth = floor(available / 3)
        let cardHeight = cardWidth * 1.25

        return VStack(spacing: 8) {
            Spacer()
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: spacing) {
                    ForEach(shopItems) { item in
                        Button {
                            selectedItem = item
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                showingDetail = true
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(item.imageName)
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(width: 48, height: 48)

                                Text(item.name)
                                    .font(.custom("PressStart2P-Regular", size: 10))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.8)

                                Text("\(item.price) coins")
                                    .font(.custom("PressStart2P-Regular", size: 10))
                                    .foregroundColor(.yellow)
                            }
                            .padding(10)
                            .frame(width: cardWidth, height: cardHeight)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.55))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.25), lineWidth: 2)
                                    )
                            )
                            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 10)
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Animations

    private func startAnimations() {
        parallaxOffset = 2
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            parallaxOffset = -2
        }
        flicker = 0.98
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            flicker = 1.0
        }
    }

    // MARK: - Audio

    private func playMusic() {
        guard let url = Bundle.main.url(forResource: "shopmusic", withExtension: "mp3") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            bgmPlayer = p
        } catch {
            print("❌ Shop BGM error:", error)
        }
    }

    private func stopMusic() {
        bgmPlayer?.setVolume(0.0, fadeDuration: 0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            self.bgmPlayer?.stop()
            self.bgmPlayer = nil
        }
    }

    private func duckBGM(_ duck: Bool) {
        let target: Float = duck ? 0.35 : 1.0
        bgmPlayer?.setVolume(target, fadeDuration: 0.15)
    }

    private func dismissDetail() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.95)) {
            showingDetail = false
        }
    }
}

// MARK: - Item Detail Card

private struct ItemDetailView: View {
    let item: ShopItem
    let onClose: () -> Void
    
    @EnvironmentObject var inventory: PlayerInventory

    var body: some View {
        VStack(spacing: 14) {
            // Art
            Image(item.imageName)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 3)

            // Title & price
            Text(item.name.uppercased())
                .font(.custom("PressStart2P-Regular", size: 14))
                .foregroundColor(.white)

            Text("COINS: \(inventory.coins)")
                .font(.custom("PressStart2P-Regular", size: 12))
                .foregroundColor(.yellow)

            // Lore / description
            Text(item.desc)
                .font(.custom("PressStart2P-Regular", size: 10))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .padding(.horizontal, 8)

            HStack(spacing: 12) {
                Button(action: onClose) {
                    Text("CLOSE")
                        .font(.custom("PressStart2P-Regular", size: 12))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    if inventory.tryBuy(item) {
                        onClose()
                    } else {
                        // Optional: show "not enough coins" feedback
                    }
                }) {
                    Text("BUY")
                        .font(.custom("PressStart2P-Regular", size: 12))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

            }
            .padding(.top, 6)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.25), lineWidth: 2)
                )
        )
        .padding(.horizontal, 24)
    }
}
