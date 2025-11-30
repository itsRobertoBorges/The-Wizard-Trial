import SwiftUI
import AVFoundation

struct WorldSelectionView: View {
    let onBack: () -> Void
    let onSelectWorld: (WorldID) -> Void

    private let bgPortal = "portal"
    @State private var showingIntro = false
    private let worlds: [WorldID] = [
        .witheringTree,
        .blackrockValley,
        .drownedSanctum,
        .lightningTemple,
        .hollowGarden,
        .towerOfBabel
    ]

    @State private var index: Int = 0
    @State private var isFading: Bool = false
    @State private var floatUp: Bool = false

    @State private var bgmPlayer: AVAudioPlayer?

    var body: some View {
        ZStack {

            // Solid black so no white edges ever show
            Color.black.ignoresSafeArea()

            // ===== Background portal =====
            GeometryReader { geo in
                Image(bgPortal)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(
                        width: geo.size.width,
                        height: geo.size.height + 80 // a bit taller than screen
                    )
                    .offset(y: 40) // push down so bottom is fully covered
                    .clipped()
                    .ignoresSafeArea()
            }

            // ===== Back Button (top-left) =====
            VStack {
                HStack {
                    Button {
                        stopMusic()
                        onBack()
                    } label: {
                        Text("BACK")
                            .font(.custom("PressStart2P-Regular", size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 44)

                    Spacer()
                }
                Spacer()
            }

            // ===== World Selection Wheel (Swipe only) =====
            GeometryReader { geo in
                let W = min(geo.size.width, 430)
                let cardW = min(W * 0.78, 340)
                let cardH = cardW * 0.8

                VStack(spacing: 18) {
                    Spacer(minLength: 80)

                    ZStack {
                        // Previous (faded, up)
                        if worlds.indices.contains(prev(index)) {
                            Image(worldImageName(for: worlds[prev(index)]))
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: cardW * 0.78, height: cardH * 0.78)
                                .opacity(0.45)
                                .offset(y: -cardH * 0.58)
                        }

                        // Next (faded, down)
                        if worlds.indices.contains(next(index)) {
                            Image(worldImageName(for: worlds[next(index)]))
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: cardW * 0.78, height: cardH * 0.78)
                                .opacity(0.45)
                                .offset(y: cardH * 0.58)
                        }

                        // Current (main, floating)
                        Image(worldImageName(for: worlds[index]))
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: cardW, height: cardH)
                            .offset(y: floatUp ? -6 : 6)
                            .shadow(color: .white.opacity(0.35), radius: 16)
                            .opacity(isFading ? 0 : 1)
                            .animation(.easeInOut(duration: 0.18), value: isFading)
                            .animation(
                                .easeInOut(duration: 2)
                                    .repeatForever(autoreverses: true),
                                value: floatUp
                            )
                    }
                    .fullScreenCover(isPresented: $showingIntro) {
                        WitheringForestIntroView {
                            showingIntro = false
                            onSelectWorld(.witheringTree)
                        }
                    }


                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if value.translation.height < -20 {
                                    moveDown()  // swipe up → next
                                } else if value.translation.height > 20 {
                                    moveUp()    // swipe down → prev
                                }
                            }
                    )

                    // SELECT button
                    Button {
                        if worlds[index] == .witheringTree {
                            stopMusic()
                            showingIntro = true
                        } else {
                            onSelectWorld(worlds[index])
                        }
                    } label: {
                        Text("SELECT")
                            .font(.custom("PressStart2P-Regular", size: 14))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.yellow, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.black.opacity(0.6), lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 60)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            startFloat()
            playMusic()
        }
        .onDisappear {
            stopMusic()
        }
    }

    // MARK: - World → image helper
    private func worldImageName(for world: WorldID) -> String {
        switch world {
        case .witheringTree:   return "witheringtree"
        case .blackrockValley: return "blackrockvalley"
        case .drownedSanctum:  return "drownedsanctum"
        case .lightningTemple: return "lightningtemple"
        case .hollowGarden:    return "hollowgarden"
        case .towerOfBabel:    return "towerofbabel"
        }
    }

    // MARK: - Wheel Helpers
    private func prev(_ i: Int) -> Int { (i - 1 + worlds.count) % worlds.count }
    private func next(_ i: Int) -> Int { (i + 1) % worlds.count }

    private func moveUp() {
        withAnimation(.easeInOut(duration: 0.2)) { isFading = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            index = prev(index)
            withAnimation(.easeInOut(duration: 0.2)) { isFading = false }
        }
    }

    private func moveDown() {
        withAnimation(.easeInOut(duration: 0.2)) { isFading = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            index = next(index)
            withAnimation(.easeInOut(duration: 0.2)) { isFading = false }
        }
    }

    private func startFloat() {
        DispatchQueue.main.async {
            floatUp = true
        }
    }

    // MARK: - Music
    private func playMusic() {
        // Make sure the file name matches exactly in your bundle
        guard let url = Bundle.main.url(forResource: "mainmenu", withExtension: "mp3") else {
            print("⚠️ Adventure Map.mp3 not found")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try AVAudioSession.sharedInstance().setActive(true)

            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 1.0
            p.play()
            bgmPlayer = p
        } catch {
            print("❌ WorldSelect BGM error:", error)
        }
    }

    private func stopMusic() {
        bgmPlayer?.setVolume(0, fadeDuration: 0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            bgmPlayer?.stop()
            bgmPlayer = nil
        }
    }
}

