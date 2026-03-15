import SwiftUI
import AVFoundation

struct WitheringForestIntroView: View {

    // MARK: - Navigation
    let onFinish: () -> Void

    // MARK: - Scenes
    @State private var currentScene = 0
    private let sceneImages = [
        "witheringforest1",
        "witheringforest2",
        "witheringforest3",
        "witheringforest4",
        "witheringforest5",
        "witheringforest6"
    ]

    private let sceneTexts = [
        "The Apprentice steps beyond the last healthy tree… and the forest falls silent.\nEvery branch droops as though strangled by unseen hands.\nThe air grows thick with decay, clinging to the lungs like damp ash.",
        "He walks on.\nThrough endless rot.\nThrough corrupted roots.\nThrough the graveyard of what was once a living kingdom.",
        "And then, towering in the choking gloom,\nthe Withering Tree.\nA colossal husk of wood and sorrow…\nthe last place the Sage of Earth was ever seen alive.",
        "He enters the once mighty tree.\nIts heart now infested with twisted beings.\nCreatures corrupted by Zethex’s necrotic power roam without mind or mercy.",
        "At the far end stands the ancient stone door…\nThe entrance to the Sage’s throne room.\nBut it is guarded by Bohban the Titan,\nZethex’s monstrous enforcer.",
        "To free the Sage of Earth…\nto cleanse the forest…\nto reclaim what life remains…\nThe Apprentice must strike down Bohban the Titan."
    ]

    // MARK: - Typewriter State
    @State private var typedText = ""
    @State private var isTyping = false
    @State private var typeTimer: Timer?
    @State private var textIndex = 0

    // MARK: - Audio
    @State private var bgmPlayer: AVAudioPlayer?
    @State private var scrollPlayer: AVAudioPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // MARK: - Cinematic Image
            GeometryReader { geo in
                Image(sceneImages[currentScene])
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: geo.size.width,
                           height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()
            }

            VStack {
                Spacer()

                // MARK: - Textbox
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

                // MARK: - Continue Button
                Button(action: nextScene) {
                    Text(currentScene == sceneTexts.count - 1 ? "BEGIN" : "CONTINUE")
                        .font(.custom("PressStart2P-Regular", size: 14))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.yellow, in: Capsule())
                }
                .padding(.top, 12)

                // MARK: - Skip Button
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
        }
        .onDisappear {
            stopAllAudio()
        }
    }

    // MARK: - Play scene
    private func startScene(_ index: Int) {
        typedText = ""
        textIndex = 0
        isTyping = true
        playScrollSound()

        let fullText = sceneTexts[index]

        // Typewriter timer
        typeTimer?.invalidate()
        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            if textIndex < fullText.count {
                let charIndex = fullText.index(fullText.startIndex, offsetBy: textIndex)
                typedText.append(fullText[charIndex])
                textIndex += 1
            } else {
                timer.invalidate()
                isTyping = false
                stopScrollSound()
            }
        }
    }

    // MARK: - Next Scene Logic
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

    // MARK: - Skip
    private func skipCinematic() {
        stopScrollSound()
        typeTimer?.invalidate()
        finish()
    }

    private func finish() {
        stopAllAudio()
        onFinish()
    }

    // MARK: - Play Background Music
    private func startMusic() {
        guard let url = Bundle.main.url(forResource: "witheringforesttheme", withExtension: "mp3") else {
            print("⚠️ witheringforesttheme.mp3 not found")
            return
        }

        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: url)
            bgmPlayer?.numberOfLoops = -1
            bgmPlayer?.volume = 1.0
            bgmPlayer?.play()
        } catch {
            print("❌ Failed to play intro music:", error)
        }
    }

    // MARK: - Scroll Sound
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

    // MARK: - Global Audio Stop
    private func stopAllAudio() {
        bgmPlayer?.stop()
        scrollPlayer?.stop()
    }
}
