import SwiftUI
import AVFoundation

struct WorldSelectionView: View {
    let onBack: () -> Void
    let onSelectWorld: (WorldID) -> Void

    private let bgPortal = "portal"
    @State private var showingIntro = false
    @State private var showingBlackrockIntro = false
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
                    .fullScreenCover(isPresented: $showingBlackrockIntro) {
                        BlackrockValleyIntroView {
                            showingBlackrockIntro = false
                            onSelectWorld(.blackrockValley)
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
                        } else if worlds[index] == .blackrockValley {
                            stopMusic()
                            showingBlackrockIntro = true
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

struct BlackrockValleyIntroView: View {
    let onFinish: () -> Void

    @State private var currentScene = 0
    @State private var introBlackOverlayOpacity: Double = 1.0
    private let sceneImages = [
        "blackrockscene1",
        "blackrockscene2",
        "blackrockscene3",
        "blackrockscene4",
        "blackrockscene 5"
    ]

    private let sceneTexts = [
        "The Blackrock Clan holds the Fire Sage captive.\nThrough ash-choked hills and the hostile Red Orcs that guard the valley, the wizard marches toward their fortress.",
        "Word spreads through the valley. The Red Orcs gather, glaring from behind jagged shields and burning braziers.",
        "Lord Zethex gave the Fire Sage to the Orcs as a prisoner. He said that in exchange, he would give the Orcs more land beyond the valley. The pact is vile, but the clan keeps its bargains.",
        "The Red Orcs are brutal, but honor-bound. They knew the wizard was coming and chose not to kill him at the gates.",
        "Instead, they bring him into Blackrock's colosseum. If the Wizard can defeat the Warchief and his armies, then the Fire Sage will be freed. The Warchief is a fearsome warrior, but he is also a man of honor."
    ]

    @State private var typedText = ""
    @State private var textIndex = 0
    @State private var typeTimer: Timer?

    @State private var bgmPlayer: AVAudioPlayer?
    @State private var scrollPlayer: AVAudioPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                Image(sceneImages[currentScene])
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .scaleEffect(currentScene == 0 ? 1.30 : 1.0)
                    .frame(
                        width: geo.size.width,
                        height: currentScene == 0 ? geo.size.height + 180 : geo.size.height
                    )
                    .offset(y: currentScene == 0 ? 60 : 0)
                    .clipped()
                    .ignoresSafeArea()
            }

            Color.black
                .opacity(introBlackOverlayOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .padding(.horizontal, 18)

                    Text(typedText)
                        .font(.custom("PressStart2P-Regular", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .multilineTextAlignment(.leading)
                }

                Button(action: nextScene) {
                    Text(currentScene == sceneTexts.count - 1 ? "BEGIN" : "CONTINUE")
                        .font(.custom("PressStart2P-Regular", size: 14))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.yellow, in: Capsule())
                }
                .padding(.top, 12)

                Button(action: skipCinematic) {
                    Text("SKIP")
                        .font(.custom("PressStart2P-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 6)
                }

                Spacer().frame(height: 20)
            }
        }
        .onAppear {
            startMusic()
            startScene(0)
            introBlackOverlayOpacity = 1.0
            withAnimation(.easeInOut(duration: 1.0)) {
                introBlackOverlayOpacity = 0
            }
        }
        .onDisappear {
            stopAllAudio()
        }
    }

    private func startScene(_ index: Int) {
        typedText = ""
        textIndex = 0
        playScrollSound()

        let fullText = sceneTexts[index]
        typeTimer?.invalidate()
        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            if textIndex < fullText.count {
                let charIndex = fullText.index(fullText.startIndex, offsetBy: textIndex)
                typedText.append(fullText[charIndex])
                textIndex += 1
            } else {
                timer.invalidate()
                stopScrollSound()
            }
        }
    }

    private func nextScene() {
        stopScrollSound()
        typeTimer?.invalidate()

        if currentScene < sceneTexts.count - 1 {
            currentScene += 1
            startScene(currentScene)
        } else {
            finish()
        }
    }

    private func skipCinematic() {
        stopScrollSound()
        typeTimer?.invalidate()
        finish()
    }

    private func finish() {
        stopAllAudio()
        onFinish()
    }

    private func startMusic() {
        guard let url = Bundle.main.url(forResource: "blackrockintrotheme", withExtension: "mp3") else {
            print("⚠️ blackrockintrotheme.mp3 not found")
            return
        }

        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: url)
            bgmPlayer?.numberOfLoops = -1
            bgmPlayer?.volume = 1.0
            bgmPlayer?.play()
        } catch {
            print("❌ Failed to play Blackrock intro music:", error)
        }
    }

    private func playScrollSound() {
        guard let url = Bundle.main.url(forResource: "textscroll", withExtension: "wav") else {
            print("⚠️ textscroll.wav missing")
            return
        }

        do {
            scrollPlayer = try AVAudioPlayer(contentsOf: url)
            scrollPlayer?.numberOfLoops = -1
            scrollPlayer?.volume = 0.8
            scrollPlayer?.play()
        } catch {
            print("❌ Scroll sound error:", error)
        }
    }

    private func stopScrollSound() {
        scrollPlayer?.stop()
        scrollPlayer = nil
    }

    private func stopAllAudio() {
        bgmPlayer?.stop()
        scrollPlayer?.stop()
    }
}
