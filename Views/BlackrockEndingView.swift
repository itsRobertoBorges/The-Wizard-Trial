import SwiftUI
import AVFoundation

struct BlackrockEndingView: View {
    let onFinish: () -> Void

    @State private var currentScene = 0
    @State private var typedText = ""
    @State private var textIndex = 0
    @State private var typeTimer: Timer?

    @State private var bgmPlayer: AVAudioPlayer?
    @State private var scrollPlayer: AVAudioPlayer?

    // Reuse frames where the story lingers on the same location or character beat.
    private let sceneImageOptions: [[String]] = [
        ["blackrockending1"],
        ["blackrockending1"],
        ["blackrockending2", "blackrockending1"],
        ["blackrockending3", "blackrockending2"],
        ["blackrockending3", "blackrockending3"],
        ["blackrockending6 1", "blackrockending4"],
        ["blackrockending7", "blackrockending4"],
        ["blackrockending8", "blackrockending5"],
        ["blackrockending6", "blackrockending6"],
        ["blackrockending9", "blackrockending7"],
    ]

    private let sceneTexts = [
        "The Warchief collapses onto the stone arena floor.\nHis massive axe crashes beside him.\nDust rises from the ground.\nThe wizard stands silently with his back to the fallen warlord.\nThe arena falls completely quiet.",
        "Thousands of red orcs stare down from the colosseum seats.\nNo one moves.\nTorches crackle in the wind.\nThe wizard lowers his staff slightly.\nThe fallen Warchief lies motionless.",
        "One orc warrior kneels.\nThen another.\nThen another.\nSoon the entire arena of red orcs bows their heads.\nWeapons lower.\nThe wizard stands alone in the center of the arena.",
        "Behind the throne platform, massive iron arena doors begin to open.\nStone grinds against stone.\nFirelight spills out from the chamber beyond.\nThe path to the prison is revealed.\nThe orcs step aside.\nNo one blocks the wizard's path.",
        "The wizard walks toward the massive arena doors.\nThe red orcs remain bowed.\nThe Warchief lies defeated behind him.\nThe doors lead to a single chamber.\nThere is a prison cell glowing with faint firelight.",
        "Inside the cell sits the Fire Sage.\nChains bind his wrists and shoulders.\nThe chains glow with dark corruption from Zethex.\nFaint firelight flickers around him.\nBut it is weak.\nAlmost dying.",
        "The chains crack.\nDark energy breaks apart like shattered glass.\nThe Fire Sage lifts his head.\nFlames begin to return around his body.\nThe prison bars melt slightly from the heat.",
        "The Fire Sage rises.\nFlames swirl around him now - bright and alive.",
        "The torches in the chamber ignite brighter.\nThe entire prison glows orange.\nThe Fire Sage places his hand over the wizard's staff.\nFire energy flows into it.\nThe wizard's crystal burns brighter than before.\n\n\"You have done what few could.\"\n\"But Zethex's corruption spreads far beyond this valley.\"",
        "\"Find the Ice Sage.\"\n\"Only together can the sages stop Zethex.\\nAnother sage remains imprisoned within the depths of the see, frozen in time.\""
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                Image(resolvedImageName(for: currentScene))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()
            }

            VStack {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .frame(height: 210)
                        .padding(.horizontal, 18)

                    Text(typedText)
                        .font(.custom("PressStart2P-Regular", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .multilineTextAlignment(.leading)
                }

                Button(action: nextScene) {
                    Text(currentScene == sceneTexts.count - 1 ? "RETURN" : "CONTINUE")
                        .font(.custom("PressStart2P-Regular", size: 14))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.yellow, in: Capsule())
                }
                .padding(.top, 12)

                Button(action: skip) {
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

    private func resolvedImageName(for index: Int) -> String {
        let candidates = sceneImageOptions[index]
        for name in candidates where UIImage(named: name) != nil {
            return name
        }
        return candidates.first ?? "blackrockending1"
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

    private func skip() {
        stopScrollSound()
        typeTimer?.invalidate()
        finish()
    }

    private func finish() {
        stopAllAudio()
        onFinish()
    }

    private func startMusic() {
        let options: [(String, String)] = [
            ("blackrockscene", "ogg"),
            ("blackrockintrotheme", "mp3"),
            ("blackrockvalleytheme", "mp3")
        ]

        for (name, ext) in options {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let player = try? AVAudioPlayer(contentsOf: url) {
                bgmPlayer = player
                bgmPlayer?.numberOfLoops = -1
                bgmPlayer?.volume = 1.0
                bgmPlayer?.play()
                return
            }
        }
    }

    private func playScrollSound() {
        guard let url = Bundle.main.url(forResource: "textscroll", withExtension: "wav") else {
            return
        }

        do {
            scrollPlayer = try AVAudioPlayer(contentsOf: url)
            scrollPlayer?.numberOfLoops = -1
            scrollPlayer?.volume = 0.8
            scrollPlayer?.play()
        } catch {
            print("Scroll sound error:", error)
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
