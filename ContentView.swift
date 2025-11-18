import SwiftUI
import SpriteKit
import Combine

struct ContentView: View {
    let world: WorldID
    let onExitToMenu: () -> Void

    // Shared inventory (coins + items)
    @EnvironmentObject var inventory: PlayerInventory

    // Keep one GameScene instance
    private let scene: GameScene
    
    // Current Wave
    @State private var currentWave: Int = 1

    // Player stats
    @State private var health: CGFloat = 100
    @State private var mana:   CGFloat = 100

    // Leveling (Stays permanent)
    @AppStorage("WT_playerLevel") private var level: Int = 1
    @AppStorage("WT_playerCurrentXP") private var currentXP: Int = 0
    @AppStorage("WT_playerXpToNext") private var xpToNext: Int = 100
    @State private var showLevelUpBanner: Bool = false

    // Whether the right stick is actively aiming/shooting
    @State private var isShooting: Bool = false

    // Run stats for death popup
    @State private var coinsThisRun: Int = 0
    @State private var xpThisRun: Int = 0
    @State private var entKills: Int = 0
    @State private var elfKills: Int = 0
    @State private var druidKills: Int = 0

    // Death popup
    @State private var showDeathPopup: Bool = false

    // Pause / Inventory popup
    @State private var showPauseOverlay: Bool = false
    @State private var isMuted: Bool = false

    /// Have we already banked this run's coins into permanent total?
    @State private var hasBankedRunCoins: Bool = false

    // Timer for mana drain / regen
    private let manaTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(world: WorldID, onExitToMenu: @escaping () -> Void) {
        self.world = world
        self.onExitToMenu = onExitToMenu

        let s = GameScene(size: UIScreen.main.bounds.size)
        s.scaleMode = .resizeFill
        self.scene = s
    }

    // MARK: - UI Subviews

    struct AnalogStickView: View {
        let size: CGFloat
        let onChange: (CGVector) -> Void   // normalized (-1...1)
        let onEnd: () -> Void

        @State private var thumbOffset: CGSize = .zero

        var body: some View {
            let radius = size / 2

            return ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 2)
                    )

                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: size * 0.45, height: size * 0.45)
                    .offset(thumbOffset)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let translation = value.translation
                        var dx = translation.width
                        var dy = translation.height

                        let dist = sqrt(dx*dx + dy*dy)
                        let maxDist = radius

                        if dist > maxDist {
                            dx = dx / dist * maxDist
                            dy = dy / dist * maxDist
                        }

                        thumbOffset = CGSize(width: dx, height: dy)

                        let normX = dx / maxDist
                        let normY = -dy / maxDist
                        onChange(CGVector(dx: normX, dy: normY))
                    }
                    .onEnded { _ in
                        thumbOffset = .zero
                        onEnd()
                    }
            )
            .frame(width: size, height: size)
        }
    }

    struct SpellButton: View {
        let icon: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(icon)
                    .font(.system(size: 22))
                    .frame(width: 52, height: 52)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.7), lineWidth: 2)
                            )
                    )
                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    struct StatusBarsView: View {
        let health: CGFloat
        let mana:   CGFloat

        var body: some View {
            VStack(spacing: 10) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 20, height: 130)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white, lineWidth: 2)
                        )

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red)
                        .frame(width: 16,
                               height: max(0, 122 * (min(health, 100) / 100)))
                        .padding(.bottom, 4)
                }

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 20, height: 130)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white, lineWidth: 2)
                        )

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue)
                        .frame(width: 16,
                               height: max(0, 122 * (min(mana, 100) / 100)))
                        .padding(.bottom, 4)
                }
            }
        }
    }

    struct LevelBarView: View {
        let level: Int
        let currentXP: Int
        let xpToNext: Int
        let currentWave: Int

        var body: some View {
            VStack(spacing: 6) {
                Text("LEVEL \(level)")
                    .font(.custom("PressStart2P-Regular", size: 12))
                    .foregroundColor(.white)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 220, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                        )

                    let progress = min(Double(currentXP) / Double(max(xpToNext, 1)), 1.0)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: 214 * progress, height: 12)
                        .padding(.leading, 4)
                }

                Text("XP: \(currentXP) / \(xpToNext)")
                    .font(.custom("PressStart2P-Regular", size: 9))
                    .foregroundColor(.white)

                Text("WAVE \(currentWave) / 49")
                    .font(.custom("PressStart2P-Regular", size: 9))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: scene)
                    .ignoresSafeArea()

                // ===== Pause button (top-left) =====
                VStack {
                    HStack {
                        Button {
                            guard !showDeathPopup else { return }
                            showPauseOverlay = true
                            scene.isPaused = true
                        } label: {
                            Text("PAUSE")
                                .font(.custom("PressStart2P-Regular", size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.leading, 16)
                        .padding(.top, 20)

                        Spacer()
                    }
                    Spacer()
                }

                // ===== Level bar (top-center) =====
                VStack {
                    HStack {
                        Spacer()
                        LevelBarView(
                            level: level,
                            currentXP: currentXP,
                            xpToNext: xpToNext,
                            currentWave: currentWave
                        )
                        .padding(.top, 44)
                        Spacer()
                    }
                    Spacer()
                }

                // ===== HP & MANA (center-left) =====
                VStack {
                    Spacer()
                    HStack {
                        StatusBarsView(health: health, mana: mana)
                            .padding(.leading, 16)
                        Spacer()
                    }
                    Spacer()
                }

                // ===== HUD + Controls (bottom) =====
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        AnalogStickView(
                            size: geo.size.width * 0.26,
                            onChange: { vector in
                                scene.setMovementInput(vector)
                            },
                            onEnd: {
                                scene.setMovementInput(.zero)
                            }
                        )
                        .padding(.leading, 40)
                        .padding(.bottom, 24)

                        Spacer()

                        ZStack {
                            AnalogStickView(
                                size: geo.size.width * 0.24,
                                onChange: { vector in
                                    let mag = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
                                    if mana <= 0 {
                                        isShooting = false
                                        scene.setAttackInput(.zero)
                                    } else {
                                        isShooting = (mag > 0.15)
                                        scene.setAttackInput(vector)
                                    }
                                },
                                onEnd: {
                                    isShooting = false
                                    scene.setAttackInput(.zero)
                                }
                            )

                            Button {
                                scene.castSpell(slot: 1)
                            } label: {
                                Image("blizzardspell")
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 0, y: -geo.size.width * 0.18)

                            Button {
                                scene.castSpell(slot: 2)
                            } label: {
                                Image("lightningshield")
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(.plain)
                            .offset(x: -geo.size.width * 0.14,
                                    y: geo.size.width * 0.04)

                            Button {
                                scene.castSpell(slot: 3)
                            } label: {
                                Image("healthpotion")
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(.plain)
                            .offset(x: geo.size.width * 0.14,
                                    y: geo.size.width * 0.04)

                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }

                // ===== Level Up banner =====
                if showLevelUpBanner {
                    VStack {
                        Spacer()
                        Text("LEVEL UP! LV \(level)")
                            .font(.custom("PressStart2P-Regular", size: 14))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.85))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.green.opacity(0.8), lineWidth: 2)
                                    )
                            )
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 8, x: 0, y: 4)
                            .padding(.bottom, 120)
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // ===== PAUSE / INVENTORY OVERLAY =====
                if showPauseOverlay {
                    Color.black.opacity(0.75)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closePauseOverlay()
                        }

                    VStack(spacing: 16) {
                        Text("INVENTORY")
                            .font(.custom("PressStart2P-Regular", size: 14))
                            .foregroundColor(.white)

                        Text("COINS: \(inventory.coins)")
                            .font(.custom("PressStart2P-Regular", size: 10))
                            .foregroundColor(.yellow)

                        let totalSlots = 16
                        let columns = Array(repeating: GridItem(.fixed(40), spacing: 6), count: 4)

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(0..<totalSlots, id: \.self) { index in
                                let item: ShopItem? =
                                    index < inventory.items.count ? inventory.items[index] : nil

                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.black.opacity(0.7))
                                        )

                                    if let item = item {
                                        Image(item.imageName)
                                            .resizable()
                                            .interpolation(.none)
                                            .scaledToFit()
                                            .padding(4)
                                    } else {
                                        Image(systemName: "square.dashed")
                                            .foregroundColor(.white.opacity(0.25))
                                            .font(.system(size: 10))
                                    }
                                }
                                .frame(width: 40, height: 40)
                            }
                        }

                        HStack(spacing: 14) {
                            Button {
                                // bank coins for this run before leaving
                                if !hasBankedRunCoins {
                                    inventory.addCoins(coinsThisRun)
                                    hasBankedRunCoins = true
                                }
                                scene.isPaused = false
                                onExitToMenu()
                            } label: {
                                Text("MAIN MENU")
                                    .font(.custom("PressStart2P-Regular", size: 11))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(0.9))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            }

                            Button {
                                isMuted.toggle()
                                scene.setMuted(isMuted)
                            } label: {
                                Text(isMuted ? "UNMUTE" : "MUTE")
                                    .font(.custom("PressStart2P-Regular", size: 11))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(0.9))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white, lineWidth: 3)
                            )
                    )
                    .padding(.horizontal, 32)
                }

                // ===== DEATH OVERLAY + POPUP =====
                if showDeathPopup {
                    Color.black
                        .opacity(0.8)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    VStack(spacing: 16) {
                        Text("YOU DIED!")
                            .font(.custom("PressStart2P-Regular", size: 18))
                            .foregroundColor(.red)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Coins collected: \(coinsThisRun)")
                            Text("XP gained: \(xpThisRun)")
                            Text("Ents defeated: \(entKills)")
                            Text("Elves defeated: \(elfKills)")
                            Text("Druids defeated: \(druidKills)")
                        }
                        .font(.custom("PressStart2P-Regular", size: 9))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)

                        HStack(spacing: 18) {
                            Button {
                                onExitToMenu()
                            } label: {
                                Text("MAIN MENU")
                                    .font(.custom("PressStart2P-Regular", size: 11))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(0.9))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            }

                            Button {
                                resetRunState()
                                scene.fullReset()
                                scene.begin()
                            } label: {
                                Text("TRY AGAIN?")
                                    .font(.custom("PressStart2P-Regular", size: 11))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(0.9))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white, lineWidth: 3)
                            )
                    )
                    .padding(.horizontal, 32)
                    .transition(.opacity)
                }
            }
        }
        // ===== Hook into GameScene events =====

        .onReceive(scene.damagePublisher) { dmg in
            guard !showDeathPopup else { return }

            let newHP = max(health - CGFloat(dmg), 0)
            health = newHP
            if newHP <= 0 {
                // bank coins once on death
                if !hasBankedRunCoins {
                    inventory.addCoins(coinsThisRun)
                    hasBankedRunCoins = true
                }

                scene.triggerGameOver()
                withAnimation(.easeInOut(duration: 0.35)) {
                    showDeathPopup = true
                }
            }
        }

        .onReceive(scene.coinsPublisher) { coins in
            if !showDeathPopup {
                coinsThisRun = coins
            }
        }

        .onReceive(scene.wavePublisher) { newWave in
            currentWave = newWave
        }

        .onReceive(manaTimer) { _ in
            if showDeathPopup || showPauseOverlay { return }

            if isShooting {
                if mana > 0 {
                    mana = max(mana - 0.5, 0)
                }
            } else {
                mana = min(mana + 0.5, 100)
            }
        }

        .onReceive(scene.xpPublisher) { gained in
            xpThisRun += gained
            gainXP(gained)

            if gained == 25 {
                entKills += 1
            } else if gained == 20 {
                elfKills += 1
            } else if gained == 40 {
                druidKills += 1
            }
        }

        .onReceive(scene.gameOverPublisher) { _ in
            if !showDeathPopup {
                if !hasBankedRunCoins {
                    inventory.addCoins(coinsThisRun)
                    hasBankedRunCoins = true
                }
                withAnimation(.easeInOut(duration: 0.35)) {
                    showDeathPopup = true
                }
            }
        }
    }

    // MARK: - Leveling logic
    
    private func maxHP(for level: Int) -> CGFloat {
        100 + CGFloat(level - 1) * 6
    }

    private func maxMana(for level: Int) -> CGFloat {
        100 + CGFloat(level - 1) * 10
    }

    private func gainXP(_ amount: Int) {
        currentXP += amount

        while currentXP >= xpToNext {
            currentXP -= xpToNext
            level += 1
            xpToNext = Int(Double(xpToNext) * 1.25)

            health = maxHP(for: level)
            mana   = maxMana(for: level)

            withAnimation(.easeInOut(duration: 0.25)) {
                showLevelUpBanner = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showLevelUpBanner = false
                }
            }
        }
    }

    // MARK: - Run reset

    private func resetRunState() {
        health = maxHP(for: level)
        mana   = maxMana(for: level)
        coinsThisRun = 0
        xpThisRun = 0
        entKills = 0
        elfKills = 0
        druidKills = 0
        showDeathPopup = false
        hasBankedRunCoins = false
    }

    private func closePauseOverlay() {
        showPauseOverlay = false
        scene.isPaused = false
    }
}
