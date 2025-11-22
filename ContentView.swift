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
    
    // Game Pause State
    @State private var wasPausedBeforeBackground = false
    
    @State private var spellCooldowns: [String: CGFloat] = [
        "manashield": 0,
        "lightningshield": 0,
        "rapidwand": 0,
        "blizzard": 0,
        "fireball": 0
    ]


    // MARK: - Game State
    @State private var currentWave: Int = 1
    @State private var health: CGFloat = 100
    @State private var mana:   CGFloat = 100
    
    //Cooldowns
    @AppStorage("WT_cooldowns") private var cooldownsData: Data = Data()
    @State private var cooldowns: [String: Double] = [:]


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
    
    // Spells
    @State private var isManaShieldActive: Bool = false
    @State private var manaShieldTimeRemaining: CGFloat = 0

    // Heal-over-time from potion
    @State private var healTicksRemaining: Int = 0
    @State private var healPerTick: CGFloat = 0
    
    // Storm aura
    @State private var isStormAuraActive: Bool = false
    @State private var stormAuraTimeRemaining: CGFloat = 0
    
    // Spell cooldown tick
    private let cooldownTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()



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
                        onMainMenu: {
                            bankCoinsIfNeededAndExitToMenu()
                            scene.stopSceneCompletely()
                            onExitToMenu()
                        },
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
                            inventory.destroyOneInInventory(item)
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
                        },
                        onRevive: {
                            revivePlayer()
                        },
                        canRevive: hasReviveItem
                    )
                }
                
                
            }
        }
        // ===== GameScene event wiring =====
        .onReceive(scene.manaSpendPublisher) { amount in
            if mana >= amount {
                mana -= amount
            }
        }
    
        .onReceive(cooldownTick) { _ in
            reduceCooldowns()
        }

        
        .onReceive(scene.damagePublisher) { dmg in
            guard !showDeathPopup else { return }

            // ⚡ LIGHTNING SHIELD FULL IMMUNITY
            if isStormAuraActive {
                return    // ignore ALL damage
            }

            // 🛡️ MANA SHIELD: absorbs hit using mana
            if isManaShieldActive {
                if mana >= 15 {
                    mana = max(mana - 15, 0)
                    scene.playManaShieldHitSound()

                    // If mana is too low for another block, disable mana shield
                    if mana < 15 {
                        isManaShieldActive = false
                        scene.setManaShield(active: false)
                    }

                    return   // No HP damage
                } else {
                    // Not enough mana → drop the shield
                    isManaShieldActive = false
                    scene.setManaShield(active: false)
                }
            }

            // ❤️ Normal HP damage
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

            // === Mana drain / regen from shooting ===
            if isShooting {
                if mana > 0 {
                    mana = max(mana - 0.5, 0)
                }
            } else {
                mana = min(mana + 0.5, maxMana(for: level))
            }

            // === Health potion heal-over-time ===
            if healTicksRemaining > 0 {
                let maxHp = maxHP(for: level)
                health = min(health + healPerTick, maxHp)
                healTicksRemaining -= 1
            }

            // === Mana shield duration ===
            if isManaShieldActive {
                manaShieldTimeRemaining -= 0.1  // timer is every 0.1s

                // Time up or mana too low → drop shield & bubble
                if manaShieldTimeRemaining <= 0 || mana < 15 {
                    isManaShieldActive = false
                    scene.setManaShield(active: false)
                }
            
            }
            
            // === Storm aura duration ===
            if isStormAuraActive {
                stormAuraTimeRemaining -= 0.1

                if stormAuraTimeRemaining <= 0 {
                    isStormAuraActive = false
                    scene.setStormAura(active: false)
                }
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
            inventory.addCoins(1000)
            
            scene.setPlayerLevel(level)
        }
        
        .onChange(of: level) { newLevel in
            scene.setPlayerLevel(newLevel)
        }

        
        // ===== App background / foreground pause handling =====
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // App going into background
            if showPauseOverlay {
                wasPausedBeforeBackground = true
            } else {
                wasPausedBeforeBackground = false
            }

            // Always pause SpriteKit when backgrounded
            scene.isPaused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // App returning to foreground
            if wasPausedBeforeBackground {
                // Stay paused if we were paused before leaving
                scene.isPaused = true
            } else {
                // Only resume if user was NOT paused
                if !showPauseOverlay && !showDeathPopup {
                    scene.isPaused = false
                }
            }
        }

    }
    
    
    

    // MARK: - Top / Left HUD Pieces

    private var topLeftPauseButton: some View {
        VStack {
            Spacer()   // push content down slightly

            HStack {
                Spacer().frame(width: 0)

                Button {
                    guard !showDeathPopup else { return }
                    showPauseOverlay = true
                    scene.isPaused = true
                } label: {
                    Text("PAUSE")
                        .font(.custom("PressStart2P-Regular", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.leading, 16)
                .padding(.top, 340)   // 💡 moves it below health+mana bars

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
                    
                    // SLOT 1 — ABOVE
                    QuickSlotButton(
                        item: inventory.quickSlots[0],
                        action: { handleQuickSlotUse(index: 0) },
                        cooldownRemaining: cooldownRemaining(for: inventory.quickSlots[0])
                    )
                    .offset(x: 0, y: -geo.size.width * 0.20)
                    
                    // SLOT 2 — RIGHT
                    QuickSlotButton(
                        item: inventory.quickSlots[1],
                        action: { handleQuickSlotUse(index: 1) },
                        cooldownRemaining: cooldownRemaining(for: inventory.quickSlots[1])
                    )
                    .offset(x: geo.size.width * 0.20, y: -geo.size.width * 0.02)
                    
                    // SLOT 3 — BELOW
                    QuickSlotButton(
                        item: inventory.quickSlots[2],
                        action: { handleQuickSlotUse(index: 2) },
                        cooldownRemaining: cooldownRemaining(for: inventory.quickSlots[2])
                    )
                    .offset(x: 0, y: geo.size.width * 0.20)
                }
                .padding(.trailing, 70)     // << 🔥 KEY FIX: pushes everything LEFT
                .padding(.bottom, 50)
            }
        }
    }

    // MARK: - Item usage

    private func handleUse(item: ShopItem) {
        switch item.imageName {
        case "healthpotion":
            useHealthPotion()
            inventory.consume(item)
        
        case "manacrystal":
            useManaCrystal()
            inventory.consume(item)

        case "manashield":
            guard trySpendMana(30) else { return }
            guard isSpellReady("manashield") else { return }
            startCooldown("manashield", 30)
            activateManaShield()
            
        case "fairydust":
            useFairyDust()
            inventory.consume(item)
        
        case "lightningshield":
            guard trySpendMana(40) else { return }
            guard isSpellReady("lightningshield") else { return }
            startCooldown("lightningshield", 45)
            scene.tryActivateLightningShield()
        
        case "rapidwand":
            guard trySpendMana(25) else { return }
            guard isSpellReady("rapidwand") else { return }
            startCooldown("rapidwand", 60)
            scene.activateRapidWand()

        
        case "blizzardspell":
            guard trySpendMana(50) else { return }
            guard isSpellReady("blizzard") else { return }
            startCooldown("blizzard", 200)
            scene.activateBlizzard()
            scene.run(.playSoundFileNamed("blizzard.wav", waitForCompletion: false))

            
        case "fireballspell":
            guard trySpendMana(15) else { return }
            guard isSpellReady("fireball") else { return }
            startCooldown("fireball", 5)
            scene.castFireball()

        
        case "iceblock":
            guard trySpendMana(35) else { return }
            guard isSpellReady("iceblock") else { return }
            startCooldown("iceblock", 60)
            scene.activateIceBlock()

        default:
            break
        }
    }


    private func activateManaShield() {
        // Need enough mana to be meaningful
        guard mana >= 15 else { return }

        isManaShieldActive = true
        manaShieldTimeRemaining = 10.0       // ⏱ lasts up to 10 seconds

        guard trySpendMana(30) else { return }
        guard isSpellReady("manashield") else { return }
        startCooldown("manashield", 25)

        scene.setManaShield(active: true)    // show bubble
        scene.playHealSound()             // shield activation sound
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func useFairyDust() {
        let maxHp = maxHP(for: level)

        // If you're already full HP, you can early return if you want
        guard health < maxHp else { return }

        // Instantly full heal
        health = maxHp

        // 🔊 play fairy dust sound
        scene.playFairyDustSound()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }


    // Revive
    
    private var hasReviveItem: Bool {
        inventory.slots.contains(where: { $0?.imageName == "revive"})
    }
    
    private func revivePlayer() {
        guard hasReviveItem else { return }

        // Remove 1 revive item
        if let index = inventory.slots.firstIndex(where: { $0?.imageName == "revive" }) {
            inventory.slots[index] = nil
        }

        // Hide death popup
        withAnimation {
            showDeathPopup = false
        }

        // Restore HP & Mana (40%)
        let maxHp = maxHP(for: level)
        let maxMn = maxMana(for: level)

        health = maxHp * 0.4
        mana   = maxMn * 0.4

        // 🔥 Fully cancel the game over freeze
        scene.cancelGameOverState()   // <-- this fixes your pause bug
        scene.isPaused = false        // safety unpause

        // Revive sound
        scene.playReviveSound()

        // Player revive animation
        scene.runReviveEffect()
    }

    private func cooldownRemaining(for item: ShopItem?) -> Double {
        guard let item = item else { return 0 }
        return cooldowns[item.cooldownKey] ?? 0
    }


    private func handleQuickSlotUse(index: Int) {
        guard let item = inventory.quickSlots[index] else { return }

        // ⛔ BLOCK usage if on cooldown
        if cooldownRemaining(for: item) > 0 {
            print("✨ \(item.imageName) is on cooldown: \(cooldownRemaining(for: item))s left")
            return
        }

        handleUse(item: item)
    }

    
    // MARK: - Spell Mana + Cooldowns

    private func trySpendMana(_ amount: CGFloat) -> Bool {
        if mana < amount { return false }
        mana -= amount
        return true
    }

    private func isSpellReady(_ key: String) -> Bool {
        spellCooldowns[key, default: 0] <= 0
    }

    private func startCooldown(_ key: String, _ duration: Double) {
        cooldowns[key] = duration
        saveCooldowns()
    }


    private func saveCooldowns() {
        if let encoded = try? JSONEncoder().encode(cooldowns) {
            cooldownsData = encoded
        }
    }

    private func reduceCooldowns() {
        for (key, value) in cooldowns {
            cooldowns[key] = max(0, value - 1)
        }
        saveCooldowns()
    }

    private func useHealthPotion() {
        let maxHp = maxHP(for: level)
        guard health < maxHp else { return }

        // Heal 50% of max HP over ~2 seconds
        let healAmount = maxHp * 0.5
        let duration: CGFloat = 2.0       // seconds
        let tickInterval: CGFloat = 0.1   // same as manaTimer
        let ticks = max(1, Int(duration / tickInterval))

        healPerTick = healAmount / CGFloat(ticks)
        healTicksRemaining = ticks

        // 🔊 sound
        scene.playHealSound()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func useManaCrystal() {
        let maxM = maxMana(for: level)
        guard mana < maxM else { return }  // already full

        mana = maxM
        scene.playPowerUpSound()
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
        coinsThisRun = 0 // RETURN TO ZERO AFTER TESTING
        xpThisRun = 0
        entKills = 0
        elfKills = 0
        druidKills = 0
        showDeathPopup = false
        hasBankedRunCoins = false
        
        //Mana shield
        isManaShieldActive = false
        scene.setManaShield(active: false)
    }

    private func bankCoinsIfNeeded() {
        guard !hasBankedRunCoins, coinsThisRun > 0 else { return }
        inventory.addCoins(coinsThisRun)
        hasBankedRunCoins = true
    }

    private func bankCoinsIfNeededAndExitToMenu() {
        bankCoinsIfNeeded()
        scene.isPaused = false
        scene.stopSceneCompletely()
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
    
    func spendMana(_ amount: CGFloat) -> Bool {
        if mana >= amount {
            mana - amount
            return true
        }
        return false
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
    let cooldownRemaining: Double

    var body: some View {
        Button {
            if item != nil && cooldownRemaining <= 0 {
                action()
            }
        } label: {
            ZStack {
                // Slot background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    )
                    .frame(width: 60, height: 60)

                // Item Icon
                if let item = item {
                    Image(item.imageName)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .opacity(cooldownRemaining > 0 ? 0.4 : 1.0)
                }

                // === COOLDOWN OVERLAY ===
                if cooldownRemaining > 0 {
                    ZStack {
                        // Dark overlay
                        Rectangle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 60, height: 60)

                        // Countdown number
                        Text("\(Int(ceil(cooldownRemaining)))")
                            .font(.custom("PressStart2P-Regular", size: 14))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
    private func cooldownMax(for item: ShopItem?) -> Double {
        guard let item = item else { return 1 }
        switch item.imageName {
        case "manashield": return 30
        case "lightningshield": return 45
        case "rapidwand": return 60
        case "blizzardspell": return 200
        case "fireballspell": return 5
        case "iceblock": return 60
        default: return 1
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
    @ObservedObject var inventory: PlayerInventory
    let isMuted: Bool
    let onClose: () -> Void
    let onMainMenu: () -> Void
    let onToggleMute: () -> Void
    let onSelectSlotItem: (ShopItem) -> Void

    @State private var draggingIndex: Int? = nil

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

            // INVENTORY GRID
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(52), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(0..<16, id: \.self) { index in
                    inventorySlot(at: index)
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

    // Single inventory slot view with drag & drop
    private func inventorySlot(at index: Int) -> some View {
        let item = inventory.slots[index]

        return Button {
            if let item = item {
                onSelectSlotItem(item)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
                    .background(
                        (draggingIndex == index
                         ? Color.white.opacity(0.15)
                         : Color.black.opacity(0.6))
                    )
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
        .onDrag {
            // Only start a meaningful drag if there is an item
            guard let item = inventory.slots[index] else {
                return NSItemProvider(object: "" as NSString)
            }
            draggingIndex = index
            return NSItemProvider(object: item.id as NSString)
        }
        .onDrop(of: ["public.text"], isTargeted: nil) { _ in
            guard let from = draggingIndex,
                  from != index else {
                draggingIndex = nil
                return false
            }

            inventory.swapSlots(from, index)   // ✅ NO '$' here
            draggingIndex = nil
            return true
        }

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
    let onRevive: () -> Void
    let canRevive: Bool
    
    
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
                
                if canRevive {
                    Button {
                        onRevive()
                    } label: {
                        Text("REVIVE")
                            .font(.custom("PressStart2P-Regular", size: 11))
                            .foregroundColor(.green)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green, lineWidth: 2)
                            )
                    }
                }
                
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
    }
}
