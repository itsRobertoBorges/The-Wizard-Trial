import SwiftUI
import AVFoundation

struct TypewriterText: View {
    let text: String
    let characterDelay: Double
    let font: Font
    var onTypingStart: (() -> Void)? = nil
    var onTypingEnd:   (() -> Void)? = nil

    @State private var displayedText = ""
    @State private var typeSoundPlayer: AVAudioPlayer?
    @State private var finished = false

    var body: some View {
        Text(displayedText)
            .font(font)
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .onAppear {
                displayedText = ""
                finished = false
                onTypingStart?()
                playTypingSound()
                typeText()
            }
            .onDisappear {
                stopTypingSound()
            }
            .contentShape(Rectangle()) // make taps register
            .onTapGesture {            // ✅ tap to skip
                guard !finished else { return }
                displayedText = text
                finished = true
                stopTypingSound()
                onTypingEnd?()
            }
    }

    // MARK: - Typewriter Logic
    private func typeText() {
        let chars = Array(text)
        var i = 0
        Timer.scheduledTimer(withTimeInterval: characterDelay, repeats: true) { t in
            if i < chars.count {
                displayedText.append(chars[i])
                i += 1
            } else {
                t.invalidate()
                finished = true
                stopTypingSound()
                onTypingEnd?()
            }
        }
    }

    // MARK: - Sound
    private func playTypingSound() {
        guard let url = Bundle.main.url(forResource: "textscroll", withExtension: "wav") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            typeSoundPlayer = p
        } catch {
            print("❌ typing SFX error:", error)
        }
    }

    private func stopTypingSound() {
        typeSoundPlayer?.stop()
        typeSoundPlayer = nil
    }
}
