import SwiftUI
import AVFoundation

struct MainMenuView: View {
    let onPlay: () -> Void
    let onShop: () -> Void

    @State private var bgmPlayer: AVAudioPlayer?
    @State private var sfxPlayer: AVAudioPlayer?
    @State private var parallaxOffset: CGFloat = 0
    @State private var flicker: Double = 1.0
    @State private var isLeaving: Bool = false
    @State private var isLoadingShop: Bool = false // 👈 NEW for shop loading screen

    @State private var titleFloatUp: Bool = false
    @State private var startGlow: Bool = false
    @State private var shopGlow: Bool = false

    private enum WheelKind { case image(name: String), emoji(symbol: String) }
    private struct WheelItem: Identifiable {
        let id = UUID()
        let title: String
        let kind: WheelKind
    }

    @State private var wheel: [WheelItem] = [
        .init(title: "Shop", kind: .image(name: "shop")),
        .init(title: "Options", kind: .emoji(symbol: "⚙️")),
        .init(title: "Credits", kind: .emoji(symbol: "📜"))
    ]
    @State private var selectedIndex: Int = 0
    @State private var showPlaceholderAlert = false
    @State private var placeholderText = ""
    
    @State private var showWorldSelect = false
    @State private var showGame = false
    @State private var showWitheringForestIntro = false


    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ===== Background =====
            GeometryReader { geo in
                if let ui = UIImage(named: "menuimage") ??
                    (Bundle.main.path(forResource: "menuimage", ofType: "png").flatMap { UIImage(contentsOfFile: $0) }) {
                    Image(uiImage: ui)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .offset(y: parallaxOffset)
                        .opacity(flicker)
                        .overlay(
                            LinearGradient(
                                colors: [Color.black.opacity(0.35), .clear, Color.black.opacity(0.25)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: parallaxOffset)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: flicker)
                }
            }

            GeometryReader { geo in
                let W = geo.size.width
                let H = geo.size.height

                let titleW = min(W * 0.75, 400)
                let titleYOffset = -H * 0.08
                let startRatio: CGFloat = 280.0 / 600.0
                let startW = min(W * 0.82, 520)
                let startH = startW * startRatio

                VStack(spacing: 0) {
                    Spacer(minLength: H * 0.10)

                    // ===== Floating Title =====
                    if let titleImg = UIImage(named: "title") ??
                        (Bundle.main.path(forResource: "title", ofType: "png").flatMap { UIImage(contentsOfFile: $0) }) {
                        Image(uiImage: titleImg)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: titleW)
                            .offset(x: 12)        // ⭐ SHIFT RIGHT
                            .offset(y: titleFloatUp ? -8 : 8)
                            .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                                       value: titleFloatUp)
                    }

                    Spacer()

                    // ===== Start Game =====
                    Button {
                        playClickSound()
                        stopMusic()
                        withAnimation(.easeInOut(duration: 0.35)) { isLeaving = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { onPlay() }
                    } label: {
                        Image("stategame")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: startW, height: startH)
                            .offset(x: 11)        // ⭐ SHIFT RIGHT
                            .shadow(color: Color.white.opacity(startGlow ? 0.75 : 0.15),
                                    radius: startGlow ? 24 : 4)
                            .overlay(
                                Image("stategame")
                                    .resizable().interpolation(.none).scaledToFit()
                                    .frame(width: startW, height: startH)
                                    .blur(radius: startGlow ? 12 : 0)
                                    .opacity(startGlow ? 0.45 : 0.0)
                            )
                            .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: startGlow)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, H * 0.05)

                    // ===== Wheel =====
                    wheelView(width: W, height: H * 0.22)
                        .offset(y: -H * 0.04) // 👈 Moved up slightly for balance

                    Spacer(minLength: H * 0.08)
                }
                .frame(width: W, height: H)
            }

            // ===== Shop Loading Screen =====
            if isLoadingShop {
                Rectangle()
                    .fill(Color.black.opacity(0.9))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .overlay(
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.8)
                            Text("Loading Shop...")
                                .font(.custom("PressStart2P-Regular", size: 12))
                                .foregroundColor(.white)
                        }
                    )
            }
        }
        .opacity(isLeaving ? 0 : 1)
        .allowsHitTesting(!isLeaving)
        .onAppear {
            playMusic()
            startAnimations()
            DispatchQueue.main.async { titleFloatUp.toggle() }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { startGlow.toggle() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { shopGlow.toggle() }
            }
        }
        .onDisappear { stopMusic() }
        .alert("Coming soon", isPresented: $showPlaceholderAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: { Text(placeholderText) })
    }

    // MARK: - Wheel
    @ViewBuilder
    private func wheelView(width: CGFloat, height: CGFloat) -> some View {
        let arrowSize: CGFloat = 44
        let cardW = min(width * 0.45, 280)
        let cardH = min(height * 0.9, 180)

        HStack(spacing: 16) {
            Button {
                playClickSound(); withAnimation(.easeInOut(duration: 0.2)) { moveLeft() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: arrowSize, height: arrowSize)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Button { selectCurrent() } label: {
                VStack(spacing: 8) {
                    switch wheel[selectedIndex].kind {
                    case .image(let name):
                        Image(name)
                            .resizable().interpolation(.none).scaledToFit()
                            .frame(width: cardW * 0.9, height: cardH * 0.6)
                            .shadow(color: Color.white.opacity(shopGlow ? 0.65 : 0.15),
                                    radius: shopGlow ? 16 : 4)
                    case .emoji(let sym):
                        Text(sym)
                            .font(.system(size: min(cardH * 0.45, 72)))
                    }

                    Text(wheel[selectedIndex].title.uppercased())
                        .font(.custom("PressStart2P-Regular", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
                .frame(width: cardW, height: cardH)
            }
            .buttonStyle(.plain)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.width < -20 {
                            withAnimation(.easeInOut(duration: 0.2)) { moveRight() }
                        } else if value.translation.width > 20 {
                            withAnimation(.easeInOut(duration: 0.2)) { moveLeft() }
                        }
                    }
            )

            Button {
                playClickSound(); withAnimation(.easeInOut(duration: 0.2)) { moveRight() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: arrowSize, height: arrowSize)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func moveLeft() { selectedIndex = (selectedIndex - 1 + wheel.count) % wheel.count }
    private func moveRight() { selectedIndex = (selectedIndex + 1) % wheel.count }

    private func selectCurrent() {
        playClickSound()
        switch wheel[selectedIndex].title {
        case "Shop":
            withAnimation(.easeInOut(duration: 0.3)) { isLoadingShop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isLoadingShop = false
                onShop()
            }
        case "Options":
            placeholderText = "Options menu will live here."
            showPlaceholderAlert = true
        case "Credits":
            placeholderText = "Credits screen will live here."
            showPlaceholderAlert = true
        default: break
        }
    }

    // MARK: - Animations
    private func startAnimations() {
        parallaxOffset = 3
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { parallaxOffset = -3 }
        flicker = 0.98
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { flicker = 1.0 }
    }

    // MARK: - Audio
    private func playMusic() {
        guard let url = Bundle.main.url(forResource: "Adventure Map", withExtension: "mp3") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            bgmPlayer = p
        } catch { print("❌ AVAudioPlayer error:", error) }
    }

    private func stopMusic() {
        bgmPlayer?.setVolume(0.0, fadeDuration: 0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            self.bgmPlayer?.stop(); self.bgmPlayer = nil
        }
    }

    private func playClickSound() {
        guard let url = Bundle.main.url(forResource: "click", withExtension: "mp3") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            sfxPlayer = player
        } catch { print("❌ Error playing click sound:", error) }
    }
}


