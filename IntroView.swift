import SwiftUI
import AVFoundation

// MARK: - Text Box (Shop-Style)
struct IntroCaptionBar: View {
    let text: String

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.65))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 2)

                Text(text)
                    .font(.custom("PressStart2P-Regular", size: bestFontSize(forWidth: geo.size.width)))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(height: 140)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func bestFontSize(forWidth w: CGFloat) -> CGFloat {
        switch w {
        case ..<340: return 10
        case ..<380: return 11
        case ..<420: return 12
        default:     return 13
        }
    }
}

// MARK: - IntroView (simple crossfade between images)
struct IntroView: View {
    var onFinished: () -> Void

    private let images = [
        "introimage1", "introimage2", "introimage3",
        "introimage4", "introimage5", "introimage6", "introimage7"
    ]

    private let lines = [
        "Long ago, before kingdoms and crowns, six sages ruled the flow of creation itself. Each embodied a primal force — Earth, Fire, Water, Lightning, Death, and Life.",
        "Together, they formed the Council of Six, uniting their power to construct the Tower of Babel — a bridge between Heaven and Earth. And for a thousand years, the world flourished.",
        "But harmony cannot exist without envy. Among the Council was Zethex, the Sage of Death. He saw the Tower not as a bridge — but as a throne.",
        "He bound the Tower to his will, twisting its divine light into necrotic shadow. Fire turned to wrath, lightning to ruin, earth to dust, water to decay, and life to chains.",
        "The five sages were sealed within their realms, their spirits imprisoned to fuel Zethex’s immortality.",
        "Centuries have passed. The Tower still looms above a dead horizon — silent, unmoving, yet alive.",
        "Your master has fallen. Only one command remains: “Free the Five, restore the balance, and confront the Lord of Death at the Tower of Babel.”"
    ]

    // Typewriter
    @State private var idx = 0
    @State private var shown = ""
    @State private var isTyping = true
    @State private var charIndex = 0
    @State private var timer: Timer?
    private let charDelay: TimeInterval = 0.028

    // Crossfade
    @State private var fadeIn = true
    private let fadeDuration: Double = 0.55

    // Audio
    @State private var bgmPlayer: AVAudioPlayer?
    @State private var typeSFX: AVAudioPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                Image(images[idx])
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .id(images[idx])                       // ensure transition runs per scene
                    .opacity(fadeIn ? 1 : 0)               // simple fade
                    .animation(.easeInOut(duration: fadeDuration), value: fadeIn)
            }

            // Skip
            VStack {
                HStack {
                    Spacer()
                    Button("Skip") {
                        stopTypingTimer()
                        stopTypingSFX()
                        stopIntroBGM()
                        onFinished()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
                    .padding(.trailing, 14)
                }
                Spacer()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IntroCaptionBar(text: shown)
                .contentShape(Rectangle())
                .onTapGesture { handleTap() }
        }
        .onAppear {
            fadeIn = true
            startTyping()
            startIntroBGM()
        }
        .onDisappear {
            stopTypingTimer()
            stopTypingSFX()
            stopIntroBGM()
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
    }

    // MARK: - Typewriter
    private func startTyping() {
        shown = ""
        isTyping = true
        charIndex = 0
        stopTypingTimer()
        stopTypingSFX()
        startTypingSFX()

        timer = Timer.scheduledTimer(withTimeInterval: charDelay, repeats: true) { t in
            let full = lines[idx]
            guard charIndex < full.count else {
                isTyping = false
                t.invalidate()
                stopTypingSFX()
                return
            }
            let i = full.index(full.startIndex, offsetBy: charIndex)
            shown.append(full[i])
            charIndex += 1
        }
    }

    private func stopTypingTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func handleTap() {
        let full = lines[idx]
        if isTyping {
            stopTypingTimer()
            shown = full
            isTyping = false
            stopTypingSFX()
        } else {
            if idx < images.count - 1 {
                // fade out current, advance, then fade in next
                withAnimation(.easeInOut(duration: fadeDuration)) {
                    fadeIn = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) {
                    idx += 1
                    fadeIn = true
                    startTyping()
                }
            } else {
                stopIntroBGM()
                onFinished()
            }
        }
    }

    // MARK: - Audio
    private func startIntroBGM() {
        guard let url =
            Bundle.main.url(forResource: "intromusic", withExtension: "mp3") ??
            Bundle.main.url(forResource: "intromusic", withExtension: "wav")
        else { return }

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
            print("❌ Intro BGM error:", error)
        }
    }

    private func stopIntroBGM() {
        bgmPlayer?.setVolume(0.0, fadeDuration: 0.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            self.bgmPlayer?.stop()
            self.bgmPlayer = nil
        }
    }

    private func startTypingSFX() {
        guard let url =
            Bundle.main.url(forResource: "textscroll", withExtension: "mp3") ??
            Bundle.main.url(forResource: "textscroll", withExtension: "wav")
        else { return }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.9
            p.prepareToPlay()
            p.play()
            typeSFX = p
        } catch {
            print("❌ Type SFX error:", error)
        }
    }

    private func stopTypingSFX() {
        typeSFX?.stop()
        typeSFX = nil
    }
}

