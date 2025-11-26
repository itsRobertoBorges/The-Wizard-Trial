import SwiftUI
import AVFoundation

struct WitheringForestIntroView: View {
    var onFinished: () -> Void

    // Your 6 cinematic images
    private let images = [
        "witheringforest1",
        "witheringforest2",
        "witheringforest3",
        "witheringforest4",
        "witheringforest5",
        "witheringforest6"
    ]

    // Typewriter text for each scene
    private let lines = [
        "The Apprentice steps beyond the last healthy tree… and the forest falls silent.\nEvery branch droops as though strangled by unseen hands.\nThe air grows thick with decay, clinging to the lungs like damp ash.",
        "He walks on.\nThrough endless rot.\nThrough corrupted roots.\nThrough the graveyard of what was once a living kingdom.",
        "And then—towering in the choking gloom—\nthe Withering Tree.\nA colossal husk of wood and sorrow… the last place the Sage of Earth was ever seen alive.",
        "With steady breath, the Apprentice enters the once-mighty tree,\nonly to find its heart infested.\nThe inhabitants of these lands—twisted, hollowed, corrupted by Zethex—roam as a mindless army.",
        "At the far end of the chamber stands the ancient stone door…\nThe entrance to the Sage’s throne room.\nBut it is sealed—guarded by Bohban the Titan.",
        "To free the Sage of Earth… to cleanse the forest… to reclaim what life remains…\nThe Apprentice must face the corrupted horde…\nand strike down Bohban the Titan."
    ]

    // MARK: - Typewriter State
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
            // Background
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                Image(images[idx])
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(fadeIn ? 1 : 0)
                    .animation(.easeInOut(duration: fadeDuration), value: fadeIn)
            }

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
                .onTapGesture { handleTap() }
        }
        .onAppear {
            fadeIn = true
            startIntroBGM()
            startTyping()
        }
        .onDisappear {
            stopTypingTimer()
            stopIntroBGM()
            stopTypingSFX()
        }
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
                // Fade out → next → fade in
                withAnimation(.easeInOut(duration: fadeDuration)) { fadeIn = false }
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
        guard let url = Bundle.main.url(forResource: "witheringforesttheme", withExtension: "mp3") else {
            print("❌ Couldn't find witheringforesttheme.mp3")
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
            print("❌ WitheringForest BGM error:", error)
        }
    }

    private func stopIntroBGM() {
        bgmPlayer?.setVolume(0, fadeDuration: 0.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            bgmPlayer?.stop()
            bgmPlayer = nil
        }
    }

    private func startTypingSFX() {
        guard let url = Bundle.main.url(forResource: "textscroll", withExtension: "mp3") else { return }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.9
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
