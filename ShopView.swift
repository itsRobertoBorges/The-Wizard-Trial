import SwiftUI
import AVFoundation

struct ShopView: View {
    let onExit: () -> Void

    @EnvironmentObject var inventory: PlayerInventory

    @State private var bgmPlayer: AVAudioPlayer?
    @State private var flicker: Double = 1.0
    @State private var parallaxOffset: CGFloat = 0
    @State private var showItems = false

    @State private var selectedItem: ShopItem? = nil
    @State private var showingDetail = false

    private let chatLine = "Welcome, traveler! Spend your hard-earned coins on powerful relics."

    var body: some View {
        ZStack {

            // ===== Background & HUD =====
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

                VStack(spacing: 12) {
                    // Top row: back button + coins
                    HStack {
                        // Back button
                        Button {
                            stopMusic()
                            onExit()
                        } label: {
                            Image("backbutton")
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

                        // Coins display (permanent)
                        Text("COINS: \(inventory.coins)")
                            .font(.custom("PressStart2P-Regular", size: 12))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                    )
                            )
                            .padding(.trailing, 16)
                            .padding(.top, 12)
                    }
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
                    currentCoins: inventory.coins,        // ✅ use inventory.coins here
                    onClose: { dismissDetail() },
                    onBuy: { shopItem in
                        if inventory.tryBuy(shopItem) {
                            // success: item added to inventory + coins deducted
                            dismissDetail()
                        } else {
                            // TODO: feedback for can't afford / inventory full
                        }
                    }
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(3)
            }
        }
        .onAppear {
            startAnimations()
            playMusic()
        }
        .onDisappear {
            stopMusic()
        }
    }

    // MARK: - Bottom Gallery

    @ViewBuilder
    private func bottomGallery(width: CGFloat, height: CGFloat) -> some View {
        let horizontalPadding: CGFloat = 16
        let spacing: CGFloat = 10
        let available = width - (horizontalPadding * 2) - (spacing * 2)
        let cardWidth = floor(available / 3)
        let cardHeight = cardWidth * 1.25

        VStack(spacing: 8) {
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

// ===== Item Detail Card =====
private struct ItemDetailView: View {
    let item: ShopItem
    let currentCoins: Int
    let onClose: () -> Void
    let onBuy: (ShopItem) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(item.imageName)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 3)

            Text(item.name.uppercased())
                .font(.custom("PressStart2P-Regular", size: 14))
                .foregroundColor(.white)

            Text("\(item.price) COINS")
                .font(.custom("PressStart2P-Regular", size: 12))
                .foregroundColor(.yellow)

            Text("You have: \(currentCoins)")
                .font(.custom("PressStart2P-Regular", size: 10))
                .foregroundColor(.white.opacity(0.8))

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

                Button(action: { onBuy(item) }) {
                    Text(item.price <= currentCoins ? "BUY" : "CAN'T AFFORD")
                        .font(.custom("PressStart2P-Regular", size: 12))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(item.price > currentCoins)
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
