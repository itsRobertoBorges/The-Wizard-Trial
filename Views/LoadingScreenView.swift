import SwiftUI
import WebKit
import AVFoundation

enum LoadingMode {
    case classic(bg: String, text: String)
    case gif(name: String)
}

struct LoadingScreenView: View {
    let duration: TimeInterval           // baseline duration (e.g., 4.0)
    let mode: LoadingMode
    var onFinished: () -> Void

    @State private var floatUp = false
    @State private var glowOn  = false
    @State private var progress: CGFloat = 0
    @State private var fadeIn = false

    // ✅ Audio
    @State private var sfxPlayer: AVAudioPlayer?
    @State private var effectiveDuration: TimeInterval = 0

    var body: some View {
        ZStack {
            switch mode {
            case .classic(let bgName, _):
                if UIImage(named: bgName) != nil {
                    Image(bgName).resizable().scaledToFill().ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
            case .gif(let gifName):
                AnimatedGIFView(gifName: gifName)
                    .ignoresSafeArea()
            }

            if case let .classic(_, textName) = mode {
                VStack(spacing: 18) {
                    Spacer()

                    Group {
                        if UIImage(named: textName) != nil && !textName.isEmpty {
                            Image(textName)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 420)
                                .offset(y: floatUp ? -8 : 8)
                                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: floatUp)
                                .shadow(color: .white.opacity(glowOn ? 0.35 : 0.05),
                                        radius: glowOn ? 18 : 2, x: 0, y: 0)
                                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: glowOn)
                        } else {
                            Text("Loading…")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Color.black.opacity(0.35), in: Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1))
                                .offset(y: floatUp ? -8 : 8)
                                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: floatUp)
                                .shadow(color: .white.opacity(glowOn ? 0.35 : 0.05),
                                        radius: glowOn ? 18 : 2, x: 0, y: 0)
                                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: glowOn)
                        }
                    }

                    GeometryReader { geo in
                        let full = min(geo.size.width * 0.7, 320)
                        let h: CGFloat = 12
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.3), lineWidth: 1))
                                .frame(width: full, height: h)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.65)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, full * progress), height: h - 4)
                                .padding(.leading, 2).padding(.vertical, 2)
                                .shadow(color: .white.opacity(0.25), radius: 3)
                                .animation(.linear(duration: effectiveDuration), value: progress)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 22)
                    .padding(.bottom, 42)

                    Spacer().frame(height: 0)
                }
                .padding(.horizontal, 24)
            }
        }
        .opacity(fadeIn ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: fadeIn)
        .onAppear {
            fadeIn = true

            // 1) Prepare & play the door open/close SFX, compute effective duration
            let audioDur = prepareAndPlayLoadingSound(named: "loadingsound")
            effectiveDuration = max(duration, audioDur > 0 ? audioDur : duration)

            // 2) Classic mode animations + synced progress bar
            if case .classic = mode {
                floatUp = true
                glowOn = true
                progress = 0
                withAnimation(.linear(duration: effectiveDuration)) { progress = 1 }
            }

            // 3) Finish when the (longer of) bar/audio completes
            DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDuration) {
                // quick fade of SFX for polish
                sfxPlayer?.setVolume(0.0, fadeDuration: 0.25)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                    sfxPlayer?.stop()
                    sfxPlayer = nil
                }
                onFinished()
            }
        }
        .transition(.opacity)
    }

    // MARK: - Audio helpers
    private func prepareAndPlayLoadingSound(named baseName: String) -> TimeInterval {
        // Try common extensions
        let exts = ["mp3", "wav", "aiff", "m4a", "caf"]
        guard let url = exts
            .compactMap({ Bundle.main.url(forResource: baseName, withExtension: $0) })
            .first
        else { return 0 }

        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)

            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            sfxPlayer = p
            return p.duration
        } catch {
            print("❌ loadingsound SFX error:", error)
            return 0
        }
    }
}
