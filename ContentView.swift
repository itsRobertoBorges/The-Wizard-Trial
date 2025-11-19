import SwiftUI
import SpriteKit
import Combine

struct ContentView: View {
    // MARK: - Dependencies
    let world: WorldID
    let onExitToMenu: () -> Void
    @EnvironmentObject var inventory: PlayerInventory

    // GameScene
    private let scene: GameScene

    // MARK: - Game State
    @State private var currentWave: Int = 1
    @State private var health: CGFloat = 100
    @State private var mana:   CGFloat = 100

    // Permanent leveling
    @AppStorage("WT_playerLevel") private var level: Int = 1
    @AppStorage("WT_playerCurrentXP") private var currentXP: Int = 0
    @AppStorage("WT_playerXpToNext") private var xpToNext: Int = 100
    @State private var showLevelUpBanner: Bool = false

    @State private var isShooting: Bool = false

    // Run stats
    @State private var coinsThisRun: Int = 0
    @State private var xpThisRun: Int = 0
    @State private var entKills: Int = 0
    @State private var elfKills: Int = 0
    @State private var druidKills: Int = 0

    // Overlays
    @State private var showDeathPopup: Bool = false
    @State private var showPauseOverlay: Bool = false
    @State private var isMuted: Bool = false

    // Inventory UI
    @State private var selectedItem: ShopItem? = nil
    @State private var showingItemMenu: Bool = false
    @State private var choosingEquipSlot: Bool = false

    // Have we already banked this run’s coins?
    @State private var hasBankedRunCoins: Bool = false

    // Mana timer
    private let manaTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    // MARK: - Init

    init(world: WorldID, onExitToMenu: @escaping () -> Void) {
        self.world = world
        self.onExitToMenu = onExitToMenu

        let s = GameScene(size: UIScreen.main.bounds.size)
        s.scaleMode = .resizeFill
        self.scene = s
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ===== SpriteKit Scene =====
                SpriteView(scene: scene)
                    .ignoresSafeArea()

                // ===== Pause (top-left) =====
                topLeftPauseButton

                // ===== Level Bar (top-center) =====
                topCenterLevelBar

                // ===== HP / Mana (left-center) =====
                leftCenterStatusBars

                // ===== Controls (bottom) =====
                bottomControls(geo: geo)

                // ===== Level Up Banner =====
                if showLevelUpBanner {
                    LevelUpBannerView(level: level)
                }

                // ===== Pause / Inventory Overlay =====
                if showPauseOverlay {
                    PauseOverlay(
                        coinsThisRun: coinsThisRun,
                        inventory: inventory,
                        isMuted: isMuted,
                        onClose: { closePauseOverlay() },
                        onMainMenu: { bankCoinsIfNeededAndExitToMenu() },
                        onToggleMute: {
                            isMuted.toggle()
                            scene.setMuted(isMuted)
                        },
                        onSelectSlotItem: { item in
                            selectedItem = item
                            showingItemMenu = true
                        }
                    )
                }

                // ===== Equip Slot Chooser =====
                if choosingEquipSlot, let item = selectedItem {
                    EquipSlotOverlay(
                        item: item,
                        onEquip: { slotIndex in
                            inventory.equip(item, to: slotIndex)
                            choosingEquipSlot = false
                            selectedItem = nil
                        },
                        onCancel: {
                            choosingEquipSlot = false
                            selectedItem = nil
                        }
                    )
                }

                // ===== Item Use / Equip / Destroy Menu =====
                if showingItemMenu, let item = selectedItem {
                    ItemActionMenuOverlay(
                        item: item,
                        onUse: {
                            handleUse(item: item)
                            showingItemMenu = false
                            selectedItem = nil
                        },
                        onEquip: {
                            showingItemMenu = false
                            choosingEquipSlot = true
                        },
                        onDestroy: {
                            inventory.destroy(item)
                            showingItemMenu = false
                            selectedItem = nil
                        },
                        onClose: {
                            showingItemMenu = false
                            selectedItem = nil
                        }
                    )
                }

                // ===== Death Popup =====
                if showDeathPopup {
                    DeathPopupOverlay(
                        coinsThisRun: coinsThisRun,
                        xpThisRun: xpThisRun,
                        entKills: entKills,
                        elfKills: elfKills,
                        druidKills: druidKills,
                        onMainMenu: {
                            bankCoinsIfNeeded()
                            onExitToMenu()
                        },
                        onTryAgain: {
                            bankCoinsIfNeeded()
                            resetRunState()
                            scene.fullReset()
                            scene.begin()
                        }
                    )
                }
            }
        }
        // ===== GameScene event wiring =====
        .onReceive(scene.damagePublisher) { dmg in
            guard !showDeathPopup else { return }

            let newHP = max(health - CGFloat(dmg), 0)
            health = newHP
            if newHP <= 0 {
                bankCoinsIfNeeded()
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
                mana = min(mana + 0.5, maxMana(for: level))
            }
        }
        .onReceive(scene.xpPublisher) { gained in
            xpThisRun += gained
            gainXP(gained)

            switch gained {
            case 25: entKills += 1
            case 20: elfKills += 1
            case 40: druidKills += 1
            default: break
            }
        }
        .onReceive(scene.gameOverPublisher) { _ in
            if !showDeathPopup {
                bankCoinsIfNeeded()
                withAnimation(.easeInOut(duration: 0.35)) {
                    showDeathPopup = true
                }
            }
        }
        .onAppear {
            resetRunState()
        }
    }

    // MARK: - Top / Left HUD Pieces

    private var topLeftPauseButton: some View {
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
    }

    private var topCenterLevelBar: some View {
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
    }

    private var leftCenterStatusBars: some View {
        VStack {
            Spacer()
            HStack {
                StatusBarsView(
                    health: health,
                    mana: mana,
                    maxHP: maxHP(for: level),
                    maxMana: maxMana(for: level)
                )
                .padding(.leading, 16)
                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - Bottom Controls

    @ViewBuilder
    private func bottomControls(geo: GeometryProxy) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                // Left analog (movement)
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

                // Right analog + quick slots
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

                    QuickSlotButton(item: inventory.quickSlots[0]) {
                        handleQuickSlotUse(index: 0)
                    }
                    .offset(x: 0, y: -geo.size.width * 0.18)

                    QuickSlotButton(item: inventory.quickSlots[1]) {
                        handleQuickSlotUse(index: 1)
                    }
                    .offset(x: -geo.size.width * 0.14,
                            y: geo.size.width * 0.04)

                    QuickSlotButton(item: inventory.quickSlots[2]) {
                        handleQuickSlotUse(index: 2)
                    }
                    .offset(x: geo.size.width * 0.14,
                            y: geo.size.width * 0.04)
                }
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Item usage

    private func handleUse(item: ShopItem) {
        switch item.imageName {
        case "healthpotion":
            useHealthPotion()
            inventory.consume(item)
        default:
            // Later: other items
            break
        }
    }

    private func handleQuickSlotUse(index: Int) {
        guard let item = inventory.quickSlots[index] else { return }
        handleUse(item: item)
    }

    private func useHealthPotion() {
        let maxHp = maxHP(for: level)
        guard health < maxHp else { return }
        let healAmount = maxHp * 0.35
        health = min(health + healAmount, maxHp)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Leveling Helpers

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

            // Full refill on level-up
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

    // MARK: - Run / Coins Helpers

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

    private func bankCoinsIfNeeded() {
        guard !hasBankedRunCoins, coinsThisRun > 0 else { return }
        inventory.addCoins(coinsThisRun)
        hasBankedRunCoins = true
    }

    private func bankCoinsIfNeededAndExitToMenu() {
        bankCoinsIfNeeded()
        scene.isPaused = false
        onExitToMenu()
    }

    private func closePauseOverlay() {
        showPauseOverlay = false
        scene.isPaused = false
    }
}

// MARK: - Subviews

// Analog stick
struct AnalogStickView: View {
    let size: CGFloat
    let onChange: (CGVector) -> Void
    let onEnd: () -> Void

    @State private var thumbOffset: CGSize = .zero

    var body: some View {
        let radius = size / 2

        ZStack {
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

                    let dist = sqrt(dx * dx + dy * dy)
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

// HP / Mana bars
struct StatusBarsView: View {
    let health: CGFloat
    let mana: CGFloat
    let maxHP: CGFloat
    let maxMana: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            bar(current: health, maxValue: maxHP, color: .red)
            bar(current: mana,   maxValue: maxMana, color: .blue)
        }
    }

    private func bar(current: CGFloat, maxValue: CGFloat, color: Color) -> some View {
        let clamped = min(Swift.max(current, 0), maxValue)
        let ratio = maxValue > 0 ? clamped / maxValue : 0

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.7))
                .frame(width: 20, height: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white, lineWidth: 2)
                )

            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 16, height: Swift.max(0, 122 * ratio))
                .padding(.bottom, 4)
        }
    }
}

// Level + XP + Wave bar
struct LevelBarView: View {
    let level: Int
    let currentXP: Int
    let xpToNext: Int
    let currentWave: Int

    private var xpProgress: CGFloat {
        guard xpToNext > 0 else { return 0 }
        let raw = CGFloat(currentXP) / CGFloat(xpToNext)
        return min(max(raw, 0), 1)
    }

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

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green)
                    .frame(width: 214 * xpProgress, height: 12)
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

// Quick slot button
struct QuickSlotButton: View {
    let item: ShopItem?
    let action: () -> Void

    var body: some View {
        Button {
            if item != nil { action() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    )
                    .frame(width: 60, height: 60)

                if let item = item {
                    Image(item.imageName)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                } else {
                    Text("-")
                        .font(.custom("PressStart2P-Regular", size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// Level up banner
struct LevelUpBannerView: View {
    let level: Int

    var body: some View {
        VStack {
            Spacer()
            Text("LEVEL UP! LVL \(level)")
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
}

// Pause / Inventory overlay
struct PauseOverlay: View {
    let coinsThisRun: Int
    let inventory: PlayerInventory
    let isMuted: Bool
    let onClose: () -> Void
    let onMainMenu: () -> Void
    let onToggleMute: () -> Void
    let onSelectSlotItem: (ShopItem) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            pauseCard
        }
    }

    private var pauseCard: some View {
        VStack(spacing: 16) {
            Text("INVENTORY")
                .font(.custom("PressStart2P-Regular", size: 12))
                .foregroundColor(.white)

            Text("COINS: \(inventory.coins)")
                .font(.custom("PressStart2P-Regular", size: 11))
                .foregroundColor(.yellow)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(52), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(0..<16, id: \.self) { index in
                    let item = inventory.slots[index]

                    Button {
                        if let item = item {
                            onSelectSlotItem(item)
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.6), lineWidth: 2)
                                .background(Color.black.opacity(0.6))
                                .frame(width: 52, height: 52)

                            if let item = item {
                                Image(item.imageName)
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)

            HStack(spacing: 14) {
                Button {
                    onMainMenu()
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
                    onToggleMute()
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
}

// Equip slot chooser
struct EquipSlotOverlay: View {
    let item: ShopItem
    let onEquip: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("EQUIP TO SLOT")
                .font(.custom("PressStart2P-Regular", size: 12))
                .foregroundColor(.white)

            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { i in
                    slotButton(for: i)
                }
            }

            Button("CANCEL") {
                onCancel()
            }
            .font(.custom("PressStart2P-Regular", size: 11))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.blue.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white, lineWidth: 2)
                )
        )
        .padding(.horizontal, 40)
    }

    private func slotButton(for index: Int) -> some View {
        Button("SLOT \(index + 1)") {
            onEquip(index)
        }
        .font(.custom("PressStart2P-Regular", size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 2)
        )
    }
}

// Item action menu (USE / EQUIP / DESTROY)
struct ItemActionMenuOverlay: View {
    let item: ShopItem
    let onUse: () -> Void
    let onEquip: () -> Void
    let onDestroy: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            actionCard
        }
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            Text(item.name.uppercased())
                .font(.custom("PressStart2P-Regular", size: 12))
                .foregroundColor(.white)

            Text(item.desc)
                .font(.custom("PressStart2P-Regular", size: 9))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button("USE") {
                onUse()
            }
            .font(.custom("PressStart2P-Regular", size: 11))
            .foregroundColor(.white)

            Button("EQUIP") {
                onEquip()
            }
            .font(.custom("PressStart2P-Regular", size: 11))
            .foregroundColor(.white)

            Button("DESTROY") {
                onDestroy()
            }
            .font(.custom("PressStart2P-Regular", size: 11))
            .foregroundColor(.red)

            Button("CLOSE") {
                onClose()
            }
            .font(.custom("PressStart2P-Regular", size: 11))
            .foregroundColor(.white)

        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.blue.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white, lineWidth: 2)
                )
        )
        .padding(.horizontal, 40)
    }
}

// Death popup
struct DeathPopupOverlay: View {
    let coinsThisRun: Int
    let xpThisRun: Int
    let entKills: Int
    let elfKills: Int
    let druidKills: Int
    let onMainMenu: () -> Void
    let onTryAgain: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.8)
                .ignoresSafeArea()

            deathCard
        }
    }

    private var deathCard: some View {
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
                    onMainMenu()
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
                    onTryAgain()
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
    }
}
