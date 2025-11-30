//
//  WitheringForestOutroView.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2025-11-27.
//


import SwiftUI
import AVFoundation

struct WitheringForestOutroView: View {

    // MARK: - Navigation
    let onFinish: () -> Void

    // MARK: - Scenes
    @State private var currentScene = 0
    private let sceneImages = [
        "witheringforestoutro1", // Bohban falls
        "witheringforestoutro2", // corruption breaks
        "witheringforestoutro3", // forest revives
        "witheringforestoutro4", // sage appears
        "witheringforestoutro5", // blessing
        "witheringforestoutro6", // bowing apprentice
        "witheringforestoutro7", // walking toward exit
        "witheringforestoutro8"  // final glowing door
    ]

    private let sceneTexts = [
        "The Titan collapses.\nHis final roar fades into the hollow chamber…\nAnd with it, the corruption clutching the forest begins to unravel.",
        "Blackened roots crumble into dust.\nThe lifeless stone breathes again.\nA wave of green light rolls outward—breaking every chain of decay.",
        "Life returns.\nRoots pulse with warmth.\nGrass rises where none has grown for years.\nThe Withering Tree… wakes.",
        "From the restored chamber, the Sage of Earth emerges.\nHoly green fire dances across ancient armor.\nA guardian reborn.",
        "He approaches the Apprentice.\nThe air hums with divine weight.\nThe forest itself bows in his presence.",
        "A hand rests on the Apprentice’s shoulder.\nNo words are needed.\nThe message is clear:\nA greater war lies ahead.",
        "The Apprentice tightens his grip on his staff.\nHe turns toward the path of light—\nready to face the next world.",
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

                // Buttons
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
        .onDisappear { stopAllAudio() }
    }

    // MARK: - Scene Typing
    private func startScene(_ index: Int) {
        typedText = ""
        textIndex = 0
        isTyping = true
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
                isTyping = false
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

    // MARK: - Music
    private func startMusic() {
        guard let url = Bundle.main.url(forResource: "witheringforestoutro", withExtension: "mp3") else {
            print("⚠️ Missing witheringforesttheme.mp3")
            return
        }

        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: url)
            bgmPlayer?.numberOfLoops = -1
            bgmPlayer?.volume = 1.0
            bgmPlayer?.play()
        } catch {
            print("❌ Music error:", error)
        }
    }

    // MARK: - Scroll Sound
    private func playScrollSound() {
        guard let url = Bundle.main.url(forResource: "textscroll", withExtension: "wav") else {
            print("⚠️ Missing textscroll.wav")
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

    // MARK: - Stop Audio
    private func stopAllAudio() {
        bgmPlayer?.stop()
        scrollPlayer?.stop()
    }
}
