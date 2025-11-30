import SpriteKit
import UIKit
import Combine
import AVFoundation
import SwiftUI

// Collision categories
struct Cat {
    static let finger:   UInt32 = 1 << 0
    static let veggie:   UInt32 = 1 << 1
    static let missile:  UInt32 = 1 << 2
    static let ent:      UInt32 = 1 << 3
    static let elf:      UInt32 = 1 << 4
    static let elfArrow: UInt32 = 1 << 5
    static let druid:    UInt32 = 1 << 6
    static let druidOrb: UInt32 = 1 << 7
}

final class GameScene: SKScene, SKPhysicsContactDelegate {
    
    // Player inventory
    private var inventory: [String: Int] = [:]

    
    // --------------------------------------------------------
    // MARK: Waves
    // --------------------------------------------------------

    // === GLOBAL SPELL COOLDOWNS ===
    // Stores:  "manashield": TimeInterval  , etc.
    private var spellCooldowns: [String: TimeInterval] = [
        "manashield": 0,
        "lightningshield": 0,
        "rapidwand": 0,
        "blizzard": 0,
        "fireball": 0
    ]
    
    // === Cooldown Timer Tick ===
    private func isSpellReady(_ name: String) -> Bool {
        return spellCooldowns[name, default: 0] == 0
    }
    
    private struct WaveConfig {
        let ents: Int
        let elves: Int
        let druids: Int
    }

    private var waves: [WaveConfig] = []
    private var currentWaveIndex: Int = -1
    private var waveInProgress: Bool = false
    var playerLevelForSpawns: Int = 1
    
    public func setPlayerLevel(_ level: Int) {
        playerLevelForSpawns = level
    }


    // MARK: - Wizard pose
    private enum WizardPose {
        case front
        case back
        case left
        case right
        case cast
    }
    
        //Spells
    private var manaShieldNode: SKNode?
 
    private var stormAuraNode: SKNode?
    private var isStormAuraActive: Bool = false
    private var stormAuraDamageAccumulator: TimeInterval = 0

    private var isRapidWandActive: Bool = false
    
    // Blizzard spell
    private var isBlizzardActive: Bool = false
    private var blizzardNodeContainer = SKNode()
    private var blizzardDamageAccumulator: TimeInterval = 0
    private var blizzardSlowMultiplier: CGFloat = 1.0
    
    // Fireball spell
    private var fireballIsActive = false   // prevents spamming if needed

    // ICE BLOCK
    private var isIceBlockActive = false
    private var iceBlockNode: SKSpriteNode?
    private var iceBlockInvulnerable = false
    private var savedAttackMultiplier: CGFloat = 1.0
    private var savedMovementVector = CGVector(dx: 0, dy: 0)
    
    private var iceBlockDamageAccumulator: TimeInterval = 0
    
    //mana spending
    private let manaSpendSubject = PassthroughSubject<CGFloat, Never>()
    var manaSpendPublisher: AnyPublisher<CGFloat, Never> {
        manaSpendSubject.eraseToAnyPublisher()
    }

    
    // Revive
    public func runReviveEffect() {
        let aura = SKShapeNode(circleOfRadius: fingerRadius * 2.5)
        aura.fillColor = UIColor.yellow.withAlphaComponent(0.3)
        aura.strokeColor = UIColor.white.withAlphaComponent(0.9)
        aura.lineWidth = 4
        aura.glowWidth = 12
        aura.zPosition = 999
        aura.position = fingerNode.position

        addChild(aura)

        let grow = SKAction.scale(to: 1.8, duration: 0.5)
        let fade = SKAction.fadeOut(withDuration: 0.5)

        aura.run(.sequence([.group([grow, fade]), .removeFromParent()]))
    }
    
    private var revivePlayer: AVAudioPlayer?
    func playReviveSound() {
        if let url = Bundle.main.url(forResource: "revivesoundeffect", withExtension: "wav") {
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.volume = 6.0   // FULL VOLUME BOOST
                p.play()
                revivePlayer = p
            } catch {
                print("revive sound error:", error)
            }
        }
    }

    //Game Over
    public func triggerGameOver() {
        isGameOver = true
        isPaused = true
    }

    public func cancelGameOverState() {
        isGameOver = false
        isPaused = false
    }

    




    
    // Mute or not to mute
    private var isMuted = false

    // ===== damage publisher =====
    private let damageSubject = PassthroughSubject<Int, Never>()
    var damagePublisher: AnyPublisher<Int, Never> { damageSubject.eraseToAnyPublisher() }
    
    // ===== XP Publisher =====
    private let xpSubject = PassthroughSubject<Int, Never>()
    var xpPublisher: AnyPublisher<Int, Never> { xpSubject.eraseToAnyPublisher() }
    
    // ===== Kill Publishers =====
    private let entKillSubject   = PassthroughSubject<Int, Never>()
    private let elfKillSubject   = PassthroughSubject<Int, Never>()
    private let druidKillSubject = PassthroughSubject<Int, Never>()
    
    var entKillPublisher: AnyPublisher<Int, Never>   { entKillSubject.eraseToAnyPublisher() }
    var elfKillPublisher: AnyPublisher<Int, Never>   { elfKillSubject.eraseToAnyPublisher() }
    var druidKillPublisher: AnyPublisher<Int, Never> { druidKillSubject.eraseToAnyPublisher() }
    
    // ===== Wave / Coins / Game Publishers =====
    private let waveSubject     = CurrentValueSubject<Int, Never>(1)
    var wavePublisher: AnyPublisher<Int, Never> { waveSubject.eraseToAnyPublisher() }

    private let coinsSubject    = PassthroughSubject<Int, Never>()
    private let startedSubject  = PassthroughSubject<Void, Never>()
    private let gameOverSubject = PassthroughSubject<Void, Never>()

    // Background
    private var arenaBackground: SKSpriteNode?

    // MARK: - Publishers for SwiftUI
    var coinsPublisher: AnyPublisher<Int, Never> { coinsSubject.eraseToAnyPublisher() }
    var startedPublisher: AnyPublisher<Void, Never> { startedSubject.eraseToAnyPublisher() }
    var gameOverPublisher: AnyPublisher<Void, Never> { gameOverSubject.eraseToAnyPublisher() }
    private let bossDefeatedSubject = PassthroughSubject<Void, Never>()
    var bossDefeatedPublisher: AnyPublisher<Void, Never> {
        bossDefeatedSubject.eraseToAnyPublisher()
    }


    private var bgmPlayer: AVAudioPlayer?
    private var isGameOver = false
    private var hasStarted = false
    public var autoStartOnPresent: Bool = true

    private var coins: Int = 0
    private var coinAccumulator: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0

    // Player collider + visuals
    private let fingerRadius: CGFloat = 36
    private let fingerNode = SKNode()
    private let fingerRing = SKShapeNode(circleOfRadius: 36)
    private var trailEmitter: SKEmitterNode?

    // Wizard sprite
    private var wizardNode: SKSpriteNode!
    private var wizardPose: WizardPose = .front
    private var wizardBaseScale: CGFloat = 1.0

    // Analog input
    private var movementInput = CGVector(dx: 0, dy: 0)
    private var attackInput   = CGVector(dx: 0, dy: 0)
    private let moveSpeed: CGFloat = 260

    // Missile
    private var lastFireTime: TimeInterval = -1_000
    private let minFireInterval: TimeInterval = 0.18
    private var attackSpeedMultiplier: CGFloat = 1.0
    
    // BOHBAN BOSS
    private var bohban: BohbanNode?
    private var lastBossUpdate: TimeInterval = 0

    
    // ENT enemies
    private var ents: [EntNode] = []
    private let entSpeed: CGFloat = 90   // tweak as needed

    // Woodland elves
    private var woodlandElves: [WoodlandElfNode] = []
    
    // Woodland druids
    private var woodlandDruids: [WoodlandDruidNode] = []

    // --------------------------------------------------------
    // MARK: Scene lifecycle
    // --------------------------------------------------------
    
    func goToMainMenu() {
        guard let view = self.view else { return }

        let menu = MainMenuView(
            onPlay: { [weak view] in
                guard let view = view else { return }
                let newScene = GameScene(size: view.bounds.size)
                newScene.scaleMode = .aspectFill
                view.presentScene(newScene, transition: .fade(withDuration: 1.0))
            },
            onShop: { [weak view] in
                guard let view = view else { return }
                let shop = ShopView(onExit: {
                    // Return to menu when exiting shop
                    self.goToMainMenu()
                })
                .environmentObject(PlayerInventory.shared)   // IMPORTANT

                let hosting = UIHostingController(rootView: shop)
                view.window?.rootViewController = hosting
            }
        )

        // Present the SwiftUI MainMenu
        let hosting = UIHostingController(rootView: menu)
        view.window?.rootViewController = hosting
    }

    func handleBohbanDefeat() {

        // Stop all actions
        self.removeAllActions()

        // Fade-to-black layer
        let black = SKSpriteNode(color: .black, size: size)
        black.zPosition = 99999
        black.alpha = 0
        black.position = CGPoint(x: size.width/2, y: size.height/2)
        addChild(black)

        black.run(.sequence([
            .fadeIn(withDuration: 1.2),
            .wait(forDuration: 0.8),
            .run { [weak self] in
                // 🔥 Notify SwiftUI that Bohban is dead → start outro
                self?.bossDefeatedSubject.send(())
            }
        ]))
    }


    override func didMove(to view: SKView) {
        buildBackgroundIfNeeded()
        layoutBackground()
        backgroundColor = .black
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        view.isMultipleTouchEnabled = true
        
        //inventory
        coins = SaveManager.shared.loadCoins()
        coinsSubject.send(coins)

        inventory = SaveManager.shared.loadInventory()

    

        configureFingerNode()
        configureWizardNode()
        configureMusic()

        fingerNode.position = CGPoint(x: size.width * 0.5, y: size.height * 0.35)

        if autoStartOnPresent && !hasStarted {
            run(.sequence([
                .wait(forDuration: 0.2),
                .run { [weak self] in self?.begin() }
            ]))
        }
    }
    
    private func trySpendMana(_ amount: CGFloat) -> Bool {
        manaSpendSubject.send(amount)
        return true
    }


    
    // End Gamescene music on exit
    public func stopSceneCompletely() {
        // Stop all actions
        removeAllActions()

        // Remove all children (missiles, enemies, shield, etc.)
        children.forEach { $0.removeAllActions() }
        removeAllChildren()

        // Stop and reset music
        bgmPlayer?.stop()
        bgmPlayer?.currentTime = 0
        bgmPlayer?.volume = 1.0
    }


    override func didChangeSize(_ oldSize: CGSize) {
        layoutBackground()
    }

    // --------------------------------------------------------
    // MARK: Public API for SwiftUI
    // --------------------------------------------------------


    // Bohban UI
    private var bohbanHealthBarBG = SKShapeNode()
    private var bohbanHealthBarFill = SKShapeNode()
    private var bohbanNameLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")

    func createBohbanHealthBar() {

        // Remove old UI if somehow exists
        bohbanHealthBarBG.removeFromParent()
        bohbanHealthBarFill.removeFromParent()
        bohbanNameLabel.removeFromParent()

        let barWidth: CGFloat = 22
        let barHeight: CGFloat = size.height * 0.42
        let xPos = size.width - 60
        let yPos = size.height / 2

        // OUTLINE
        let bgRect = CGRect(x: -barWidth/2, y: -barHeight/2, width: barWidth, height: barHeight)
        bohbanHealthBarBG = SKShapeNode(rect: bgRect, cornerRadius: 4)
        bohbanHealthBarBG.strokeColor = .white
        bohbanHealthBarBG.lineWidth = 4
        bohbanHealthBarBG.fillColor = .clear
        bohbanHealthBarBG.position = CGPoint(x: xPos, y: yPos)
        bohbanHealthBarBG.zPosition = 999
        addChild(bohbanHealthBarBG)

        // FILL BAR
        let fillRect = CGRect(x: -barWidth/2 + 3,
                              y: -barHeight/2 + 3,
                              width: barWidth - 6,
                              height: barHeight - 6)

        bohbanHealthBarFill = SKShapeNode(rect: fillRect, cornerRadius: 3)
        bohbanHealthBarFill.fillColor = .green
        bohbanHealthBarFill.strokeColor = .clear
        bohbanHealthBarFill.position = CGPoint(x: xPos, y: yPos)
        bohbanHealthBarFill.zPosition = 1000
        addChild(bohbanHealthBarFill)

        // NAME LABEL
        bohbanNameLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        bohbanNameLabel.text = "BOHBAN THE TITAN"
        bohbanNameLabel.fontSize = 18
        bohbanNameLabel.fontColor = .white
        bohbanNameLabel.position = CGPoint(x: xPos + 40, y: yPos)
        bohbanNameLabel.zRotation = .pi / 2
        bohbanNameLabel.zPosition = 1001
        addChild(bohbanNameLabel)
    }

    
    func updateBohbanHealthBar(currentHP: Int, maxHP: Int) {
        let percent = max(0, min(1, CGFloat(currentHP) / CGFloat(maxHP)))

        let fullHeight = size.height * 0.42 - 6
        let barWidth: CGFloat = 22 - 6
        let newHeight = fullHeight * percent

        let fillRect = CGRect(
            x: -barWidth/2,
            y: -(fullHeight/2),
            width: barWidth,
            height: newHeight
        )

        bohbanHealthBarFill.path = CGPath(rect: fillRect, transform: nil)
    }





    public func begin() {
        guard !hasStarted, !isGameOver else { return }
        hasStarted = true
        startedSubject.send(())
        startScoringAndSpawns()
        
    }
 
    
    func showOrbExplosion(at p: CGPoint) {
        let explosion = SKEmitterNode()

        explosion.particleTexture = SKTexture(imageNamed: "pixel")  // a tiny 1x1 pixel (or I can generate one)
        explosion.particleBirthRate = 500
        explosion.numParticlesToEmit = 40
        explosion.particleLifetime = 0.35
        explosion.particleLifetimeRange = 0.2

        explosion.particlePositionRange = CGVector(dx: 20, dy: 20)

        explosion.particleSpeed = 180
        explosion.particleSpeedRange = 60

        explosion.particleAlpha = 1.0
        explosion.particleAlphaSpeed = -3.0

        explosion.particleScale = 3.0
        explosion.particleScaleSpeed = -3.0

        explosion.particleColor = UIColor.green
        explosion.particleColorBlendFactor = 1.0

        explosion.position = p
        explosion.zPosition = 999

        addChild(explosion)

        explosion.run(.sequence([
            .wait(forDuration: 0.45),
            .removeFromParent()
        ]))
    }

    
    public func fullReset() {

        // STOP EVERYTHING
        removeAllActions()
        children.forEach { $0.removeAllActions() }
        children.forEach { $0.removeFromParent() }

        // Restore background
        arenaBackground = nil
        buildBackgroundIfNeeded()
        layoutBackground()

        // Reset arrays
        ents.removeAll()
        woodlandElves.removeAll()
        woodlandDruids.removeAll()

        // Reset boss
        bohban?.removeAllActions()
        bohban?.removeFromParent()
        bohban = nil

        // Remove Bohban UI
        bohbanHealthBarBG.removeFromParent()
        bohbanHealthBarFill.removeFromParent()
        bohbanNameLabel.removeFromParent()

        // Reset states
        isGameOver = false
        hasStarted = false
        coins = 0
        coinAccumulator = 0
        lastUpdate = 0

        wizardPose = .front
        updateWizardTexture()

        coinsSubject.send(0)
        waveSubject.send(1)

        // Reset BGM
        bgmPlayer?.stop()
        bgmPlayer?.currentTime = 0
        bgmPlayer?.volume = 1.0

        // reset waves
        setupWaves()
    }


    
    // Bohban
    
    func spawnBohban() {
        if bohban != nil { return }

        let boss = BohbanNode(screenWidth: size.width, scene: self)
        bohban = boss

        addChild(boss)
        boss.runEntrance(in: self)
        createBohbanHealthBar()
    }





    // --------------------------------------------------------
    // MARK: Waves / Spawning + scoring
    // --------------------------------------------------------

    //level up sound
    // Level up (you already have this)
    public func playLevelUpSound() {
        run(.playSoundFileNamed("levelUp.wav", waitForCompletion: false))
    }

    // 🔊 Health potion
    func playHealSound() {
        let action = SKAction.playSoundFileNamed("healingpotion.wav", waitForCompletion: false)
        run(action)
    }

    // 🔊 Mana crystal / power-up
    func playPowerUpSound() {
        let action = SKAction.playSoundFileNamed("powerUp.wav", waitForCompletion: false)
        run(action)
    }

    // 🔊 Mana shield takes a hit
    func playManaShieldHitSound() {
        let action = SKAction.playSoundFileNamed("manashieldhit.wav", waitForCompletion: false)
        run(action)
    }
    
    func playFairyDustSound() {
        let action = SKAction.playSoundFileNamed("fairydust.wav", waitForCompletion: false)
        run(action)
        
        // ✨ Golden aura around the wizard
            // Base radius off wizard size
            let wizardWidth  = wizardNode.frame.width
            let wizardHeight = wizardNode.frame.height
            let wizardDiameter = max(wizardWidth, wizardHeight)

            let auraRadius = wizardDiameter * 13.8   // tweak if you want bigger/smaller
            let aura = SKShapeNode(circleOfRadius: auraRadius)

            aura.fillColor = UIColor.yellow.withAlphaComponent(0.35)
            aura.strokeColor = UIColor.orange.withAlphaComponent(0.8)
            aura.lineWidth = 4
            aura.zPosition = 80
            aura.glowWidth = 12
            aura.blendMode = .add

            aura.position = .zero
            wizardNode.addChild(aura)

            // Scale + fade animation
            let grow = SKAction.scale(to: 1.4, duration: 0.45)
            let fade = SKAction.fadeOut(withDuration: 0.45)
            let group = SKAction.group([grow, fade])

            aura.run(.sequence([group, .removeFromParent()]))
    }
    
    func playLightningSpellSound(){
        let action = SKAction.playSoundFileNamed("lightningspell.wav", waitForCompletion: false)
        run(action)
    }

    private func startNextWave() {
        currentWaveIndex += 1

        // 49 waves total → index 0...48
        if currentWaveIndex >= waves.count {
            // All waves done – later: spawn boss here
            // spawnBoss()
            return
        }

        let config = waves[currentWaveIndex]
        waveInProgress = true

        // tell SwiftUI which wave we’re on (1-based)
        waveSubject.send(currentWaveIndex + 1)

        // Spawn ents for this wave
        for _ in 0..<config.ents {
            spawnEnt()
        }

        // Spawn elves for this wave
        for _ in 0..<config.elves {
            spawnWoodlandElf()
        }

        //Spawn druids
         for _ in 0..<config.druids { spawnWoodlandDruid() }
    }

    private func setupWaves() {
        waves.removeAll()

        for wave in 1...49 {
            let entsCount  = min(1 + wave / 3, 12)
            let elvesCount = max(0, (wave - 4) / 3)

            // Druids disabled by default
            var druidsCount = 0

            // Only spawn druids if PLAYER LEVEL ≥ 20
            if playerLevelForSpawns >= 20 && wave >= 20 {
                // Gradually increase druid count
                druidsCount = min((wave - 19) / 8, 3)
            }

            waves.append(WaveConfig(
                ents: entsCount,
                elves: elvesCount,
                druids: druidsCount
            ))
        }

        currentWaveIndex = -1
        waveInProgress = false
    }

    
    // Mute option in pause menu

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        bgmPlayer?.volume = muted ? 0.0 : 1.0
        
        if !isMuted {
            run(.playSoundFileNamed("autoattacksound.mp3", waitForCompletion: false))
        }
    }
    

    private func startScoringAndSpawns() {
        lastUpdate = 0
        coinAccumulator = 0

        setupWaves()
        startNextWave()

        bgmPlayer?.play()
    }

    private func scheduleEntSpawns() {
        removeAction(forKey: "entSpawns")

        let spawn = SKAction.run { [weak self] in
            self?.spawnEnt()
        }

        let wait = SKAction.wait(forDuration: 12.0, withRange: 6.0)
        run(.repeatForever(.sequence([spawn, wait])), withKey: "entSpawns")
    }

    private func scheduleElfSpawns() {
        removeAction(forKey: "elfSpawns")

        let spawn = SKAction.run { [weak self] in
            self?.spawnWoodlandElf()
        }

        let wait = SKAction.wait(forDuration: 10.0, withRange: 5.0)
        run(.repeatForever(.sequence([spawn, wait])), withKey: "elfSpawns")
    }
    
    private func scheduleDruidSpawns() {
        removeAction(forKey: "druidSpawns")

        let spawn = SKAction.run { [weak self] in
            self?.spawnWoodlandDruid()
        }

        let wait = SKAction.wait(forDuration: 14.0, withRange: 6.0)
        run(.repeatForever(.sequence([spawn, wait])), withKey: "druidSpawns")
    }

     func spawnWoodlandDruid() {
        guard !isGameOver else { return }

        // pick a side: 0=left,1=right,2=top,3=bottom
        let side = Int.random(in: 0..<4)
        let marginX: CGFloat = 40
        let marginY: CGFloat = 60

        let center: CGPoint

        switch side {
        case 0: // left
            center = CGPoint(x: marginX,
                             y: CGFloat.random(in: size.height * 0.35...size.height * 0.8))
        case 1: // right
            center = CGPoint(x: size.width - marginX,
                             y: CGFloat.random(in: size.height * 0.35...size.height * 0.8))
        case 2: // top
            center = CGPoint(x: CGFloat.random(in: size.width * 0.2...size.width * 0.8),
                             y: size.height - marginY)
        default: // bottom
            center = CGPoint(x: CGFloat.random(in: size.width * 0.2...size.width * 0.8),
                             y: size.height * 0.55) // slightly above player area
        }

        let targetDiameter = fingerRadius * 3.2
        let druid = WoodlandDruidNode(targetDiameter: targetDiameter,
                                      startCenter: center)
        addChild(druid)
        woodlandDruids.append(druid)
    }

    // --------------------------------------------------------
    // MARK: Analog inputs
    // --------------------------------------------------------

    public func setMovementInput(_ v: CGVector) {
        movementInput = v
    }

    public func setAttackInput(_ v: CGVector) {
        attackInput = v
    }

    public func castSpell(slot: Int) {
        guard !isGameOver else { return }

        if slot == 2 {
            let mag = hypot(attackInput.dx, attackInput.dy)
            guard mag > 0.1 else { return }

            let target = CGPoint(
                x: fingerNode.position.x + attackInput.dx * 300,
                y: fingerNode.position.y + attackInput.dy * 300
            )

            let now = CACurrentMediaTime()
            fireMissile(toward: target, atTime: now)
        }
    }

    // --------------------------------------------------------
    // MARK: Enemy spawn telegraph (veggies – currently unused)
    // --------------------------------------------------------

     func showWizardCast(
        at position: CGPoint,
        radius r: CGFloat,
        duration: TimeInterval = 2.0,
        completion: @escaping () -> Void
    ) {
        let wizard = SKSpriteNode(imageNamed: "firewizard")
        wizard.position = position
        wizard.zPosition = 100
        wizard.alpha = 0.0
        addChild(wizard)

        let desiredDiameter: CGFloat = fingerRadius * 2.0
        let scale = desiredDiameter / max(wizard.size.width, wizard.size.height)
        wizard.setScale(scale)

        wizard.run(
            .sequence([
                .group([
                    .fadeIn(withDuration: 0.1),
                    .scale(to: scale * 1.1, duration: 0.1)
                ]),
                .wait(forDuration: duration - 0.2),
                .fadeOut(withDuration: 0.15),
                .removeFromParent()
            ])
        ) {
            completion()
        }
    }

    // --------------------------------------------------------
    // MARK: ENT spawn
    // --------------------------------------------------------
    
     func spawnEnt() {
        guard !isGameOver else { return }

        let margin: CGFloat = 60
        let spawnX = CGFloat.random(in: margin...(size.width - margin))
        let spawnY = size.height + margin
        let pos    = CGPoint(x: spawnX, y: spawnY)

        let targetDiameter = fingerRadius * 3.0
        let ent = EntNode(targetDiameter: targetDiameter)
        ent.position = pos
        addChild(ent)
        ents.append(ent)
    }

    // --------------------------------------------------------
    // MARK: Woodland elf spawn
    // --------------------------------------------------------

     func spawnWoodlandElf() {
        guard !isGameOver else { return }

        let marginX: CGFloat = 40
        let spawnY = CGFloat.random(in: (size.height * 0.45)...(size.height * 0.8))
        let fromLeft = Bool.random()

        let direction: WoodlandElfNode.Direction = fromLeft ? .fromLeft : .fromRight
        let spawnX: CGFloat
        let targetX: CGFloat

        if fromLeft {
            spawnX = -marginX
            targetX = CGFloat.random(in: size.width * 0.22...size.width * 0.35)
        } else {
            spawnX = size.width + marginX
            targetX = CGFloat.random(in: size.width * 0.65...size.width * 0.78)
        }

        let targetDiameter = fingerRadius * 5.0
        let elf = WoodlandElfNode(targetDiameter: targetDiameter,
                                  direction: direction,
                                  targetX: targetX)
        elf.position = CGPoint(x: spawnX, y: spawnY)
        addChild(elf)
        woodlandElves.append(elf)
    }

    // --------------------------------------------------------
    // MARK: Autoshoot missile (player)
    // --------------------------------------------------------

    private func fireMissile(toward target: CGPoint, atTime now: TimeInterval) {
        if now - lastFireTime < (minFireInterval / attackSpeedMultiplier) { return }
        lastFireTime = now

        if isRapidWandActive {
            run(.playSoundFileNamed("rapidshoot.wav", waitForCompletion: false))
        } else {
            run(.playSoundFileNamed("autoattacksound.mp3", waitForCompletion: false))
        }


        let start = fingerNode.position
        let dx = target.x - start.x
        let dy = target.y - start.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len
        let uy = dy / len

        let r: CGFloat = 8
        let projectileName = isRapidWandActive ? "rapid_orb" : "autoshoot"

        let missile = SKSpriteNode(imageNamed: projectileName)
        missile.texture?.filteringMode = .nearest
        missile.size = CGSize(width: r * 6, height: r * 6)
        missile.position = start
        missile.zPosition = 6


        let body = SKPhysicsBody(circleOfRadius: r)
        body.isDynamic = true
        body.affectedByGravity = false
        body.categoryBitMask = Cat.missile
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.veggie | Cat.ent | Cat.elf | Cat.druid
        body.linearDamping = 0
        missile.physicsBody = body

        let speed: CGFloat = 680
        body.velocity = CGVector(dx: ux * speed, dy: uy * speed)

        addChild(missile)
    }

    // --------------------------------------------------------
    // MARK: Touch handling
    // --------------------------------------------------------

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !hasStarted {
            begin()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { }

    // --------------------------------------------------------
    // MARK: Frame update
    // --------------------------------------------------------

    override func update(_ currentTime: TimeInterval) {
        guard hasStarted, !isGameOver else { return }
        if lastUpdate == 0 { lastUpdate = currentTime }
        if lastBossUpdate == 0 { lastBossUpdate = currentTime }


        let dt = min(currentTime - lastUpdate, 1/30)
        lastUpdate = currentTime
        
        //cool down
        for (spell, timeLeft) in spellCooldowns {
            if timeLeft > 0 {
                spellCooldowns[spell] = max(0, timeLeft - dt)
            }
        }

        // Movement
        let step = moveSpeed * CGFloat(dt)
        fingerNode.position.x += movementInput.dx * step
        fingerNode.position.y += movementInput.dy * step

        // Bounds
        let margin: CGFloat = 10
        fingerNode.position.x = max(margin, min(size.width - margin, fingerNode.position.x))
        fingerNode.position.y = max(margin, min(size.height - margin, fingerNode.position.y))
        
        if isBlizzardActive {
            blizzardDamageAccumulator += dt

            while blizzardDamageAccumulator >= 0.2 {   // every 0.2 sec
                blizzardDamageAccumulator -= 0.2

                // === ENT DAMAGE ===
                for ent in ents {
                    let died = ent.takeDamage(20)
                    if died { awardXP(20); entKillSubject.send(1) }
                    ent.speedMultiplier = blizzardSlowMultiplier
                }

                // === ELF DAMAGE ===
                for elf in woodlandElves {
                    let died = elf.takeDamage(20)
                    if died { awardXP(15); elfKillSubject.send(1) }
                    elf.speedMultiplier = blizzardSlowMultiplier
                }

                // === DRUID DAMAGE ===
                for druid in woodlandDruids {
                    let died = druid.takeDamage(20)
                    if died { awardXP(30); druidKillSubject.send(1) }
                    druid.speedMultiplier = blizzardSlowMultiplier
                }

                // === ⭐️ BOHBAN DAMAGE ⭐️ ===
                if let boss = bohban, boss.parent != nil {
                    let died = boss.takeDamage(20)

                    // Update boss HP bar
                    updateBohbanHealthBar(currentHP: boss.hp, maxHP: 2000)

                    if died {
                        // Remove UI
                        bohbanHealthBarBG.removeFromParent()
                        bohbanNameLabel.removeFromParent()
                    }
                }
            }
        }

        
        // === Update Bohban (attacks, movement timing) ===
        if let boss = bohban {
            let dt = currentTime - lastBossUpdate
            lastBossUpdate = currentTime
            boss.update(dt: dt, playerPosition: fingerNode.position, scene: self)
        }
        
        func showBohbanExplosion(at p: CGPoint) {
            let node = SKSpriteNode(imageNamed: "bohbanexplode")
            node.zPosition = 999
            node.position = p
            node.alpha = 0.0
            node.setScale(0.1)

            addChild(node)

            let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.05)
            let grow = SKAction.scale(to: 1.4, duration: 0.25)
            let fadeOut = SKAction.fadeOut(withDuration: 0.25)

            node.run(.sequence([
                fadeIn,
                grow,
                fadeOut,
                .removeFromParent()
            ]))
        }



        // ===== FIREBALL BOUNCING =====
        for node in children {
            guard let sprite = node as? SKSpriteNode else { continue }
            if sprite.texture?.description.contains("fireball") != true { continue }

            guard let body = sprite.physicsBody else { continue }

            var bounces = sprite.userData?["bounces"] as? Int ?? 0

            // Check horizontal screen bounds
            if sprite.position.x <= 20 || sprite.position.x >= size.width - 20 {
                body.velocity.dx = -body.velocity.dx
                bounces += 1
            }

            // Check vertical bounds
            if sprite.position.y <= 20 || sprite.position.y >= size.height - 20 {
                body.velocity.dy = -body.velocity.dy
                bounces += 1
            }

            sprite.userData?["bounces"] = bounces

            if bounces >= 8 {
                // Fade out → remove
                sprite.run(.sequence([
                    .fadeOut(withDuration: 0.2),
                    .removeFromParent()
                ]))
            }
        }

       
        // === Storm aura damage over time ===
        if isStormAuraActive {
            stormAuraDamageAccumulator += dt

            // 100 DPS → 10 damage every 0.1 seconds
            while stormAuraDamageAccumulator >= 0.1 {
                stormAuraDamageAccumulator -= 0.1

                // Smaller damage radius
                let auraRadius: CGFloat = 10

                let center = fingerNode.position

                // ENT damage
                for ent in ents {
                    guard ent.parent != nil else { continue }
                    let d = hypot(ent.position.x - center.x, ent.position.y - center.y)
                    if d <= auraRadius {
                        let died = ent.takeDamage(10)
                        if died {
                            awardXP(25)
                            entKillSubject.send(1)
                        }
                    }
                }

                // ELF damage
                for elf in woodlandElves {
                    guard elf.parent != nil else { continue }
                    let d = hypot(elf.position.x - center.x, elf.position.y - center.y)
                    if d <= auraRadius {
                        let died = elf.takeDamage(10)
                        if died {
                            awardXP(20)
                            elfKillSubject.send(1)
                        }
                    }
                }

                // DRUID damage
                for druid in woodlandDruids {
                    guard druid.parent != nil else { continue }
                    let d = hypot(druid.position.x - center.x, druid.position.y - center.y)
                    if d <= auraRadius {
                        let died = druid.takeDamage(10)
                        if died {
                            awardXP(40)
                            druidKillSubject.send(1)
                        }
                    }
                }
                
                for druid in woodlandDruids {
                    guard druid.parent != nil else { continue }
                    let d = hypot(druid.position.x - center.x, druid.position.y - center.y)
                    if d <= auraRadius {
                        let died = druid.takeDamage(10)
                        if died {
                            awardXP(40)
                            druidKillSubject.send(1)
                        }
                    }
                }
                
                // === BOHBAN (Boss) ===
                if let boss = bohban, boss.parent != nil {
                    let d = hypot(boss.position.x - center.x, boss.position.y - center.y)
                    if d <= auraRadius {

                        let died = boss.takeDamage(25)   // or whatever storm aura damage you want

                        // Update UI
                        updateBohbanHealthBar(currentHP: boss.hp, maxHP: 2000)

                        if died {
                            // Remove UI
                            bohbanHealthBarBG.removeFromParent()
                            bohbanNameLabel.removeFromParent()
                        }
                    }
                }

            }
        }
        
        // === ICE BLOCK CONTACT DAMAGE ===
        if isIceBlockActive {
            iceBlockDamageAccumulator += dt

            while iceBlockDamageAccumulator >= 0.1 {
                iceBlockDamageAccumulator -= 0.1
                        
                let center = fingerNode.position
                let radius: CGFloat = max(wizardNode.frame.width, wizardNode.frame.height) * 0.8

                // ENT
                for ent in ents {
                    let d = hypot(ent.position.x - center.x, ent.position.y - center.y)
                    if d <= radius {
                        let died = ent.takeDamage(20)
                        if died { awardXP(25); entKillSubject.send(1) }
                    }
                }

                // ELF
                for elf in woodlandElves {
                    let d = hypot(elf.position.x - center.x, elf.position.y - center.y)
                    if d <= radius {
                        let died = elf.takeDamage(2)
                        if died { awardXP(20); elfKillSubject.send(1) }
                    }
                }

                // DRUID
                for druid in woodlandDruids {
                    let d = hypot(druid.position.x - center.x, druid.position.y - center.y)
                    if d <= radius {
                        let died = druid.takeDamage(20)
                        if died { awardXP(40); druidKillSubject.send(1) }
                    }
                }

                // ⭐️ === BOHBAN DAMAGE === ⭐️
                if let boss = bohban, boss.parent != nil {
                    let d = hypot(boss.position.x - center.x, boss.position.y - center.y)
                    if d <= radius {
                        let died = boss.takeDamage(20)

                        // Update health bar
                        updateBohbanHealthBar(currentHP: boss.hp, maxHP: 2000)

                        if died {
                            bohbanHealthBarBG.removeFromParent()
                            bohbanNameLabel.removeFromParent()
                        }
                    }
                }
            }
        }


        

        // Move ents toward player
        for ent in ents {
            guard ent.parent != nil else { continue }

            let dx = fingerNode.position.x - ent.position.x
            let dy = fingerNode.position.y - ent.position.y
            let dist = hypot(dx, dy)
            if dist < 4 { continue }

            let ux = dx / dist
            let uy = dy / dist

            ent.position.x += ux * entSpeed * CGFloat(dt)
            ent.position.y += uy * entSpeed * CGFloat(dt)
        }

        // Update woodland elves (movement + shooting)
        for elf in woodlandElves {
            elf.update(dt: dt, playerPosition: fingerNode.position)
        }
        
        // Update woodland druids (floating + orbs)
        for druid in woodlandDruids {
            druid.update(dt: dt, playerPosition: fingerNode.position)
        }

        // 🔫 Auto-shoot from right analog
        let attackMag = hypot(attackInput.dx, attackInput.dy)
        if attackMag > 0.2 {
            let now = CACurrentMediaTime()
            let target = CGPoint(
                x: fingerNode.position.x + attackInput.dx * 300,
                y: fingerNode.position.y + attackInput.dy * 300
            )
            fireMissile(toward: target, atTime: now)
        }

        // Wizard animation
        refreshWizardPose()
        
        wizardNode.isHidden = false
        wizardNode.alpha = 1.0
        wizardNode.zPosition = 210
        fingerNode.zPosition = 200

        // Score (coins over time)
        coinAccumulator += dt
        while coinAccumulator >= 1 {
            coinAccumulator -= 1
            coins += 1
            coinsSubject.send(coins)
            SaveManager.shared.saveCoins(coins)
        }

        cleanupOffscreen()
        ents.removeAll { $0.parent == nil }
        woodlandElves.removeAll { $0.parent == nil }
        woodlandDruids.removeAll { $0.parent == nil }
        
        if waveInProgress &&
            ents.isEmpty &&
            woodlandElves.isEmpty &&
            woodlandDruids.isEmpty {

            waveInProgress = false

            // If final wave (49), spawn boss instead of next wave
            if currentWaveIndex + 1 >= 49 {
                run(.sequence([
                    .wait(forDuration: 1.5),
                    .run { [weak self] in self?.startBohbanBossFight() }
                ]))
            } else {
                run(.sequence([
                    .wait(forDuration: 2.0),
                    .run { [weak self] in self?.startNextWave() }
                ]))
            }
        }
    }
    
    func startBohbanBossFight() {
        
        // Change background
        if let bg = arenaBackground {
            bg.texture = SKTexture(imageNamed: "bohbanarena")
            bg.texture?.filteringMode = .nearest
            layoutBackground()
        }

        // Stop current music
        bgmPlayer?.stop()

        // Play Bohban theme
        if let url = Bundle.main.url(forResource: "bohbantheme", withExtension: "mp3") {
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.numberOfLoops = -1
                p.volume = 1.0
                p.play()
                bgmPlayer = p
            } catch {
                print("ERROR playing Bohban theme:", error)
            }
        }

        // Spawn the boss
        bohban = BohbanNode(screenWidth: size.width, scene: self)
        bohban = BohbanNode(screenWidth: size.width, scene: self)
        if let b = bohban {
            addChild(b)
            createBohbanHealthBar()
            b.runEntrance(in: self)

            // 💥 Connect boss-death callback
            b.onBossDeath = { [weak self] in
                self?.handleBohbanDefeat()
            }
        }

    }
    
    func onBohbanDeath() {
        // Stop his music immediately
        bgmPlayer?.setVolume(0.0, fadeDuration: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.bgmPlayer?.stop()
            self.bgmPlayer = nil
        }

        bgmPlayer = nil

        // Optional: fade whole screen and return to menu
        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.goToMainMenu()
            }
        ]))
    }

    
    private func deactivateIceBlock() {
        guard isIceBlockActive else { return }

        isIceBlockActive = false
        iceBlockInvulnerable = false

        // Restore movement + attacks
        attackSpeedMultiplier = savedAttackMultiplier

        // Remove visuals
        iceBlockNode?.removeFromParent()
        iceBlockNode = nil

        if let glow = wizardNode.childNode(withName: "iceblockGlow") {
            glow.removeFromParent()
        }
    }
    
    public func tryCastFireball() {
        guard trySpendMana(15) == true else {
            run(.playSoundFileNamed("notenoughmana.wav", waitForCompletion: false))
            return
        }

        castFireball()
    }

    
    public func castFireball() {
        guard !isGameOver else { return }

        // Spend mana
        guard trySpendMana(15) else {
            run(.playSoundFileNamed("notenoughmana.wav", waitForCompletion: false))
            return
        }
        guard isSpellReady("fireball") else { return }

        let dx = movementInput.dx
        let dy = movementInput.dy
        let mag = hypot(dx, dy)

        // Default direction is upward if not aiming
        let ux: CGFloat
        let uy: CGFloat

        if mag < 0.2 {
            ux = 0
            uy = 1     // straight up fireball
        } else {
            ux = dx / mag
            uy = dy / mag
        }

        spawnFireball(ux: ux, uy: uy)
    }


    private func spawnFireball(ux: CGFloat, uy: CGFloat) {

        let speed: CGFloat = 520
        let fireballSize: CGFloat = 42   // adjust if needed

        let fb = SKSpriteNode(imageNamed: "fireball")
        fb.zPosition = 100
        fb.position = fingerNode.position
        fb.setScale(fireballSize / max(fb.size.width, fb.size.height))
        fb.blendMode = .add
        fb.alpha = 0.95

        // Keep track of bounces
        fb.userData = ["bounces": 0]

        // Physics
        let body = SKPhysicsBody(circleOfRadius: fireballSize * 0.4)
        body.isDynamic = true
        body.affectedByGravity = false
        body.categoryBitMask = Cat.missile
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.ent | Cat.elf | Cat.druid
        body.linearDamping = 0
        fb.physicsBody = body

        body.velocity = CGVector(dx: ux * speed, dy: uy * speed)

        addChild(fb)
    }
    
    public func tryActivateIceBlock() {
        guard trySpendMana(35) == true else {
            run(.playSoundFileNamed("notenoughmana.wav", waitForCompletion: false))
            return
        }

        activateIceBlock()
    }

    
    public func activateIceBlock() {
        guard !isIceBlockActive else { return }

        isIceBlockActive = true
        iceBlockInvulnerable = true

        // Save values
        savedMovementVector = movementInput
        savedAttackMultiplier = attackSpeedMultiplier
        
        guard trySpendMana(35) else { return }
        guard isSpellReady("iceblock") else { return }


        // Freeze movement + attacks
        movementInput = .zero
        attackInput = .zero
        attackSpeedMultiplier = 0

        // Create ice block sprite
        let block = SKSpriteNode(imageNamed: "iceblockspell")
        block.zPosition = 300
        block.alpha = 0.95
        block.blendMode = .alpha

        let w = wizardNode.frame.width
        let h = wizardNode.frame.height
        let diameter = max(w, h) * 11.2
        let base = max(block.size.width, block.size.height)
        block.setScale(diameter / base)

        wizardNode.addChild(block)
        block.position = .zero
        iceBlockNode = block

        // Glow aura
        let glow = SKShapeNode(circleOfRadius: diameter * 10.6)
        glow.fillColor = UIColor.cyan.withAlphaComponent(0.20)
        glow.strokeColor = UIColor.white.withAlphaComponent(0.5)
        glow.glowWidth = 10
        glow.zPosition = 301
        glow.name = "iceblockGlow"
        wizardNode.addChild(glow)

        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.5, duration: 0.5),
            .fadeAlpha(to: 0.2, duration: 0.5)
        ])))

        // Duration
        run(.sequence([
            .wait(forDuration: 10.0),
            .run { [weak self] in self?.deactivateIceBlock() }
        ]))
    }

    public func tryActivateBlizzard() {
        guard trySpendMana(50) == true else {
            run(.playSoundFileNamed("notenoughmana.wav", waitForCompletion: false))
            return
        }

        activateBlizzard()
    }

    
    public func activateBlizzard() {
        guard !isBlizzardActive else { return }

        isBlizzardActive = true
        blizzardSlowMultiplier = 0.75   // 25% slow
        addChild(blizzardNodeContainer)
        
        guard trySpendMana(50) else { return }
        guard isSpellReady("blizzard") else { return }

        // Swap wizard to cast pose
        let oldTexture = wizardNode.texture
        wizardNode.texture = SKTexture(imageNamed: "wizardspell")
        wizardNode.texture?.filteringMode = .nearest

        // Blizzard lasts 10 seconds
        run(.sequence([
            .wait(forDuration: 10.0),
            .run { [weak self] in
                self?.stopBlizzard()
                self?.wizardNode.texture = oldTexture
            }
        ]))

        // Begin spawning falling ice bolts
        spawnBlizzardBolts()
    }
    
    private func dropOneBlizzardBolt() {
        guard isBlizzardActive else { return }

        let xPos = CGFloat.random(in: size.width * 0.1 ... size.width * 0.9)
        let startY = size.height + 40

        let bolt = SKSpriteNode(imageNamed: "blizzardbolt")   // your uploaded asset name
        bolt.zPosition = 90
        bolt.alpha = 0.92
        bolt.blendMode = .add
        bolt.setScale(0.05)

        bolt.position = CGPoint(x: xPos, y: startY)
        blizzardNodeContainer.addChild(bolt)

        // Glow pulse
        let glowUp = SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        let glowDown = SKAction.fadeAlpha(to: 0.85, duration: 0.1)
        bolt.run(.repeatForever(.sequence([glowUp, glowDown])))

        // Fall action
        let fall = SKAction.moveBy(x: 0, y: -size.height - 80, duration: 1.15)
        bolt.run(.sequence([fall, .removeFromParent()]))
    }
    
        private func spawnBlizzardBolts() {
            // Spawn 6 bolts per second (one every 0.16 sec)
            let spawn = SKAction.run { [weak self] in
                self?.dropOneBlizzardBolt()
            }

            let wait = SKAction.wait(forDuration: 0.16)

            let sequence = SKAction.sequence([spawn, wait])

            blizzardNodeContainer.run(.repeatForever(sequence), withKey: "BlizzardSpawner")
        }
    
    private func stopBlizzard() {
        isBlizzardActive = false
        blizzardSlowMultiplier = 1.0

        // Stop the bolt spawner
        removeAction(forKey: "BlizzardBoltSpawner")

        // Remove visuals
        blizzardNodeContainer.removeAllActions()
        blizzardNodeContainer.removeAllChildren()
        blizzardNodeContainer.removeFromParent()
    }



    
    // Mana shield bubble
    public func tryActivateManaShield() {
        guard trySpendMana(30) == true else {
            run(.playSoundFileNamed("notenoughmana.wav", waitForCompletion: false))
            return
        }

        guard manaShieldNode == nil else { return }

        setManaShield(active: true)

        // Auto-disable in 10 sec
        run(.sequence([
            .wait(forDuration: 10.0),
            .run { [weak self] in self?.setManaShield(active: false) }
        ]))
    }

    func setManaShield(active: Bool) {
        if active {
            guard manaShieldNode == nil else { return }

            let bubble = SKSpriteNode(imageNamed: "manashieldeffect")
            bubble.zPosition = 55
            bubble.alpha = 0.85   // transparent look

            // Attach to wizard first so frame values are valid
            wizardNode.addChild(bubble)
            bubble.position = .zero

            // --- SCALE LOGIC ---

            // Try to base size on wizard
            var wizardWidth  = wizardNode.frame.width
            var wizardHeight = wizardNode.frame.height

            // Fallback in case wizard frame is zero or tiny
            if wizardWidth < 10 || wizardHeight < 10 {
                // use your fingerRadius as a reasonable base
                wizardWidth  = fingerRadius * 2.0
                wizardHeight = fingerRadius * 2.0
            }

            let wizardDiameter = max(wizardWidth, wizardHeight)

            // Make bubble MUCH larger than wizard (try 2.8x)
            let bubbleDiameter = wizardDiameter * 10.8

            let baseBubbleSize = max(bubble.size.width, bubble.size.height)
            let scale = bubbleDiameter / max(baseBubbleSize, 1)  // avoid divide by 0

            bubble.setScale(scale)

            // Store it
            manaShieldNode = bubble

            // Pulse animation
            let pulseUp = SKAction.scale(to: scale * 1.08, duration: 0.6)
            let pulseDown = SKAction.scale(to: scale * 0.95, duration: 0.6)
            let pulse = SKAction.repeatForever(.sequence([pulseUp, pulseDown]))
            bubble.run(pulse)

        } else {
            manaShieldNode?.run(
                .sequence([
                    .fadeOut(withDuration: 0.2),
                    .removeFromParent()
                ])
            )
            manaShieldNode = nil
        }
    }
    
    public func tryActivateRapidWand() {
        guard trySpendMana(25) == true else {
            run(.playSoundFileNamed("notenoughmana.wav", waitForCompletion: false))
            return
        }

        activateRapidWand()
    }

    public func activateRapidWand() {
        // Prevent stacking
        removeAction(forKey: "RapidWandTimer")

        isRapidWandActive = true
        attackSpeedMultiplier = 1.5   // +50% attack speed
        guard trySpendMana(25) else { return }
        guard isSpellReady("rapidwand") else { return }

        let wait = SKAction.wait(forDuration: 20.0)
        let block = SKAction.run { [weak self] in
            self?.attackSpeedMultiplier = 1.0
            self?.isRapidWandActive = false
        }

        run(.sequence([wait, block]), withKey: "RapidWandTimer")
    }

    public func tryActivateLightningShield() {
        // Mana + cooldown are already handled in ContentView
        guard !isStormAuraActive else { return }

        setStormAura(active: true)
        playLightningSpellSound()

        // Auto-disable after 10 seconds
        run(.sequence([
            .wait(forDuration: 10.0),
            .run { [weak self] in self?.setStormAura(active: false) }
        ]))
    }


    func setStormAura(active: Bool) {
        if active {
            guard stormAuraNode == nil else { return }

            // Big lightning aura sprite (use your own art name here)
            let aura = SKSpriteNode(imageNamed: "lightningshieldeffect")
            aura.zPosition = 60
            aura.alpha = 0.9
            aura.blendMode = .add

            // Scale much larger than wizard
            let w = wizardNode.frame.width
            let h = wizardNode.frame.height
            let wizardDiameter = max(w, h)

            let auraDiameter = wizardDiameter * 13.0   // 🔥 much bigger than mana shield
            let baseSize = max(aura.size.width, aura.size.height)
            let scale = auraDiameter / max(baseSize, 1)
            aura.setScale(scale)

            wizardNode.addChild(aura)
            aura.position = .zero

            // Spin + pulse a bit
            let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 2.0)
            let rotForever = SKAction.repeatForever(rotate)

            let pulseUp = SKAction.scale(to: scale * 1.05, duration: 0.5)
            let pulseDown = SKAction.scale(to: scale * 0.97, duration: 0.5)
            let pulse = SKAction.repeatForever(.sequence([pulseUp, pulseDown]))

            aura.run(rotForever)
            aura.run(pulse)

            stormAuraNode = aura
            isStormAuraActive = true
            stormAuraDamageAccumulator = 0

        } else {
            isStormAuraActive = false
            stormAuraDamageAccumulator = 0

            stormAuraNode?.run(
                .sequence([
                    .fadeOut(withDuration: 0.25),
                    .removeFromParent()
                ])
            )
            stormAuraNode = nil
        }
    }

    // XP Gainz
    private func awardXP(_ amount: Int) {
        xpSubject.send(amount)
    }

    private func cleanupOffscreen() {
        let pad: CGFloat = 100
        for node in children {
            if node is BohbanNode {continue}
            guard let cat = node.physicsBody?.categoryBitMask else { continue }

            if cat == Cat.missile ||
               cat == Cat.ent ||
               cat == Cat.elf ||
               cat == Cat.elfArrow ||
               cat == Cat.druid ||
               cat == Cat.druidOrb {

                if node.position.x < -pad ||
                    node.position.x > size.width + pad ||
                    node.position.y < -pad ||
                    node.position.y > size.height + pad {

                    node.removeFromParent()
                }
            }
        }
    }

    // --------------------------------------------------------
    // MARK: Physics contacts
    // --------------------------------------------------------

    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA
        let b = contact.bodyB
        let mask = a.categoryBitMask | b.categoryBitMask
        
        //Bohban Damage
        if mask == (Cat.missile | Cat.druid) {
            let bossBody = (a.categoryBitMask == Cat.druid) ? a : b
            let missileBody = (bossBody == a) ? b : a

            if let bohban = bossBody.node as? BohbanNode {
                let died = bohban.takeDamage(10)   // same as Ent/Elf damage

                missileBody.node?.removeFromParent()

                if died {
                    bohbanHealthBarBG.removeFromParent()
                    bohbanNameLabel.removeFromParent()
                }
            }
        }

        
        // ================================================
        // FIREBALL HIT (strong projectile, 50 damage)
        // ================================================
        if mask == (Cat.missile | Cat.ent)
            || mask == (Cat.missile | Cat.elf)
            || mask == (Cat.missile | Cat.druid) {

            let enemyBody: SKPhysicsBody
            let fireballBody: SKPhysicsBody

            if a.categoryBitMask == Cat.missile {
                fireballBody = a
                enemyBody = b
            } else {
                fireballBody = b
                enemyBody = a
            }

            // Make sure it’s REALLY the fireball (not autoshoot)
            if let fb = fireballBody.node as? SKSpriteNode,
               fb.texture?.description.contains("fireball") == true {

                // ENT
                if let ent = enemyBody.node as? EntNode {
                    let died = ent.takeDamage(50)
                    if died { awardXP(25); entKillSubject.send(1) }
                }

                // ELF
                if let elf = enemyBody.node as? WoodlandElfNode {
                    let died = elf.takeDamage(50)
                    if died { awardXP(20); elfKillSubject.send(1) }
                }

                // DRUID
                if let druid = enemyBody.node as? WoodlandDruidNode {
                    let died = druid.takeDamage(50)
                    if died { awardXP(40); druidKillSubject.send(1) }
                }
                
                if let boss = bohban, boss.parent != nil {
                    let died = boss.takeDamage(20)
                    
                    updateBohbanHealthBar(currentHP: boss.hp, maxHP: 2000)
                    
                    if died {
                        bohbanHealthBarBG.removeFromParent()
                        bohbanNameLabel.removeFromParent()
                    }
                }

                // Hit effect
                showHitPop(at: fireballBody.node!.position)

                return
            }
        }


//        // Player hit by veggie (if you ever bring them back)
//        if mask == (Cat.finger | Cat.veggie) {
//            if a.categoryBitMask == Cat.veggie { a.node?.removeFromParent() }
//            if b.categoryBitMask == Cat.veggie { b.node?.removeFromParent() }
//
//            damageSubject.send(10)
//            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
//            return
//        }

        // Player hit by ENT → explode + 25 damage
        // Player hit by ENT → explode + 25 damage (unless shielded)
        if mask == (Cat.finger | Cat.ent) {
            let entBody = (a.categoryBitMask == Cat.ent) ? a : b
            if let ent = entBody.node as? EntNode {
                ent.explode()
            }

            // ⚡ Lightning Shield OR 🧊 Ice Block = no HP loss
            if isStormAuraActive || isIceBlockActive {
                return
            }

            damageSubject.send(25)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }


        // Missile hits ENT
        if mask == (Cat.missile | Cat.ent) {
            let entBody: SKPhysicsBody
            let missileBody: SKPhysicsBody

            if a.categoryBitMask == Cat.ent {
                entBody = a
                missileBody = b
            } else {
                entBody = b
                missileBody = a
            }

            if let ent = entBody.node as? EntNode {
                let died = ent.takeDamage(10)
                if died {
                    awardXP(25)           // XP for killing an Ent
                    entKillSubject.send(1) // 🔹 notify SwiftUI: 1 ent kill
                }
            }

            missileBody.node?.removeFromParent()

            let hitPoint = contact.contactPoint
            showHitPop(at: hitPoint)
            return
        }

        // Missile hits woodland elf
        if mask == (Cat.missile | Cat.elf) {
            let elfBody: SKPhysicsBody
            let missileBody: SKPhysicsBody

            if a.categoryBitMask == Cat.elf {
                elfBody = a
                missileBody = b
            } else {
                elfBody = b
                missileBody = a
            }

            if let elf = elfBody.node as? WoodlandElfNode {
                let died = elf.takeDamage(10)
                if died {
                    awardXP(20)           // XP for killing an Elf
                    elfKillSubject.send(1) // 🔹 notify SwiftUI: 1 elf kill
                }
            }

            missileBody.node?.removeFromParent()
            let hitPoint = contact.contactPoint
            showHitPop(at: hitPoint)
            return
        }

        // Player hit by elf arrow
        if mask == (Cat.finger | Cat.elfArrow) {
            let arrowBody = (a.categoryBitMask == Cat.elfArrow) ? a : b
            arrowBody.node?.removeFromParent()

            // Shields eat the hit, no HP loss
            if isStormAuraActive || isIceBlockActive {
                return
            }

            damageSubject.send(15)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }

        // Player hit by druid orb
        if mask == (Cat.finger | Cat.druidOrb) {

            let orbBody = (a.categoryBitMask == Cat.druidOrb) ? a : b
            let hitPos = orbBody.node?.position ?? .zero

            orbBody.node?.removeFromParent()
            bohban?.showExplosion(at: hitPos, scene: self)

            // Shields absorb it
            if isStormAuraActive || isIceBlockActive {
                return
            }

            damageSubject.send(35)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }



        
        // Missile hits woodland druid
        if mask == (Cat.missile | Cat.druid) {
            let druidBody: SKPhysicsBody
            let missileBody: SKPhysicsBody

            if a.categoryBitMask == Cat.druid {
                druidBody = a
                missileBody = b
            } else {
                druidBody = b
                missileBody = a
            }

            if let druid = druidBody.node as? WoodlandDruidNode {
                let died = druid.takeDamage(10)
                if died {
                    awardXP(40)              // XP for killing a Druid (strongest)
                    druidKillSubject.send(1) // 🔹 notify SwiftUI: 1 druid kill
                }
            }

            missileBody.node?.removeFromParent()

            let hitPoint = contact.contactPoint
            showHitPop(at: hitPoint)
            return
        }
    }

    private func showHitPop(at p: CGPoint) {
        let pop = SKShapeNode(circleOfRadius: 10)
        pop.fillColor = .white
        pop.strokeColor = .clear
        pop.alpha = 0.85
        pop.position = p
        pop.zPosition = 50
        addChild(pop)

        let grow = SKAction.scale(to: 2.0, duration: 0.15)
        let fade = SKAction.fadeOut(withDuration: 0.15)

        pop.run(.sequence([
            .group([grow, fade]),
            .removeFromParent()
        ]))
    }

    // --------------------------------------------------------
    // MARK: Game Over
    // --------------------------------------------------------

    private func handleGameOver() {
        if isGameOver { return }
        isGameOver = true

        removeAction(forKey: "spawns")
        removeAction(forKey: "entSpawns")
        removeAction(forKey: "elfSpawns")
        removeAction(forKey: "druidSpawns")

        bgmPlayer?.setVolume(0.0, fadeDuration: 0.3)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.bgmPlayer?.stop()
            self?.bgmPlayer?.currentTime = 0
            self?.bgmPlayer?.volume = 1.0
        }

        gameOverSubject.send(())
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // --------------------------------------------------------
    // MARK: Wizard node visuals
    // --------------------------------------------------------

    private func configureFingerNode() {
        let body = SKPhysicsBody(circleOfRadius: fingerRadius)
        body.isDynamic = false
        body.categoryBitMask = Cat.finger
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.veggie | Cat.ent | Cat.elfArrow | Cat.druidOrb | Cat.elf | Cat.druid

        fingerNode.physicsBody = body
        fingerNode.zPosition = 40
        addChild(fingerNode)

        fingerRing.strokeColor = .white
        fingerRing.lineWidth = 2
        fingerRing.alpha = 0.15
        fingerNode.addChild(fingerRing)

        let dot = makeCircleTexture(diameter: 5, color: .white)
        let trail = makeTrail(texture: dot)
        trailEmitter = trail
        fingerNode.addChild(trail)
    }

    private func configureWizardNode() {
        let tex = SKTexture(imageNamed: "wizardforward")
        tex.filteringMode = .nearest

        wizardNode = SKSpriteNode(texture: tex)
        wizardNode.zPosition = 50

        let desiredDiameter = fingerRadius * 2.0
        wizardBaseScale = desiredDiameter / max(tex.size().width, tex.size().height)
        wizardNode.setScale(wizardBaseScale)

        fingerNode.addChild(wizardNode)
    }

    private func refreshWizardPose() {
        // If attack stick is moving
        if hypot(attackInput.dx, attackInput.dy) > 0.2 {
            if wizardPose != .cast {
                wizardPose = .cast
                updateWizardTexture()
            }
            return
        }

        let mv = movementInput
        if hypot(mv.dx, mv.dy) < 0.15 { return }

        var newPose: WizardPose

        if abs(mv.dy) >= abs(mv.dx) {
            newPose = mv.dy > 0 ? .front : .back
        } else {
            newPose = mv.dx > 0 ? .right : .left
        }

        if newPose != wizardPose {
            wizardPose = newPose
            updateWizardTexture()
        }
    }

    private func updateWizardTexture() {
        let texName: String

        switch wizardPose {
        case .front:
            texName = "wizardforward"
        case .back:
            texName = "wizardbackward"
        case .cast:
            // TEMP: reuse forward sprite until you have a real cast sprite
            texName = "wizardforward"
        case .left, .right:
            texName = "wizardfacingleft"
        }

        let tex = SKTexture(imageNamed: texName)
        tex.filteringMode = .nearest
        wizardNode.texture = tex

        var scale = wizardBaseScale
        if wizardPose == .front { scale *= 1.1 }

        if wizardPose == .right {
            wizardNode.xScale = -scale
            wizardNode.yScale =  scale
        } else {
            wizardNode.xScale =  scale
            wizardNode.yScale =  scale
        }
    }

    // --------------------------------------------------------
    // MARK: Helpers
    // --------------------------------------------------------

    private func pickSpawnPosition(margin: CGFloat) -> CGPoint {
        let x = CGFloat.random(in: margin...(size.width - margin))
        let y = CGFloat.random(in: (size.height * 0.55)...(size.height - margin))
        return CGPoint(x: x, y: y)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func nudgePosition(_ p: CGPoint, awayFrom center: CGPoint, minDistance: CGFloat) -> CGPoint {
        let dx = p.x - center.x
        let dy = p.y - center.y
        var len = hypot(dx, dy)
        if len == 0 { len = 0.001 }
        if len >= minDistance { return p }
        let s = minDistance / len
        return CGPoint(x: center.x + dx * s, y: center.y + dy * s)
    }

    private func makeCircleTexture(diameter: CGFloat, color: UIColor) -> SKTexture {
        let r = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let img = r.image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter))).fill()
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        return tex
    }

    private func makeTrail(texture: SKTexture) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.particleBirthRate = 120
        e.particleLifetime = 0.4
        e.particleAlpha = 0.9
        e.particleAlphaSpeed = -2
        e.particleScale = 0.22
        e.particleScaleSpeed = -0.35
        e.particleBlendMode = .add
        e.particlePositionRange = CGVector(dx: 6, dy: 6)
        e.targetNode = self
        return e
    }

    // --------------------------------------------------------
    // MARK: Background + Music
    // --------------------------------------------------------

    private func buildBackgroundIfNeeded() {
        guard arenaBackground == nil else { return }
        let bg = SKSpriteNode(imageNamed: "witheringforest")
        bg.zPosition = -100
        bg.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        bg.texture?.filteringMode = .nearest
        addChild(bg)
        arenaBackground = bg
    }

    private func layoutBackground() {
        guard let bg = arenaBackground, let tex = bg.texture else { return }

        bg.position = CGPoint(x: size.width / 2, y: size.height / 2)

        let scaleX = size.width / tex.size().width
        let scaleY = size.height / tex.size().height
        bg.setScale(max(scaleX, scaleY))
    }

    private func configureMusic() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        guard let url = Bundle.main.url(forResource: "Battle", withExtension: "mp3") else { return }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 1.0
            p.prepareToPlay()
            bgmPlayer = p
        } catch {
            print("Audio error:", error)
        }
    }
}
