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
    static let shaman:   UInt32 = 1 << 8
    static let shamanrock: UInt32 = 1 << 10
    static let spearman: UInt32 = 1 << 11
}

final class GameScene: SKScene, SKPhysicsContactDelegate {

    // Player inventory
    private var inventory: [String: Int] = [:]

    let world: WorldID

    init(size: CGSize, world: WorldID = .witheringTree) {
        self.world = world
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // --------------------------------------------------------
    // MARK: Waves
    // --------------------------------------------------------

    // === GLOBAL SPELL COOLDOWNS ===
    private var spellCooldowns: [String: TimeInterval] = [
        "manashield": 0,
        "lightningshield": 0,
        "rapidwand": 0,
        "blizzard": 0,
        "fireball": 0
    ]

    private func isSpellReady(_ name: String) -> Bool {
        return spellCooldowns[name, default: 0] == 0
    }

    private struct WaveConfig {
        let ents: Int
        let elves: Int
        let druids: Int
    }
    
    private struct BlackrockWaveConfig {
        let axeThrowers: Int
        let shamans: Int
        let spearmen: Int
    }
    
    private var blackrockWaves: [BlackrockWaveConfig] = []
    private var currentBlackrockWaveIndex: Int = -1
    private var blackrockWaveInProgress: Bool = false

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

    // Spells
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
    private var fireballIsActive = false

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
                p.volume = 6.0
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
    private let entSpeed: CGFloat = 90

    // Woodland elves
    private var woodlandElves: [WoodlandElfNode] = []

    // Woodland druids
    private var woodlandDruids: [WoodlandDruidNode] = []

    // ====BLACKROCK VALLEY====
    // Blackrock Valley Axe Throwers
    private var blackrockAxeThrowers: [BlackrockAxeThrowerNode] = []
    private var blackrockShamans: [BlackrockShamanNode] = []
    private var blackrockSpearmen: [BlackrockSpearmanNode] = []
    
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
                    self.goToMainMenu()
                })
                .environmentObject(PlayerInventory.shared)

                let hosting = UIHostingController(rootView: shop)
                view.window?.rootViewController = hosting
            }
        )

        let hosting = UIHostingController(rootView: menu)
        view.window?.rootViewController = hosting
    }

    func handleBohbanDefeat() {

        removeAllActions()

        let black = SKSpriteNode(color: .black, size: size)
        black.zPosition = 99999
        black.alpha = 0
        black.position = CGPoint(x: size.width/2, y: size.height/2)
        addChild(black)

        black.run(.sequence([
            .fadeIn(withDuration: 1.2),
            .wait(forDuration: 0.8),
            .run { [weak self] in
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
        
        if world == .blackrockValley {
            run(.sequence([
                .wait(forDuration: 0.5),
                .run { [weak self] in
                    self?.spawnBlackrockShaman()
                    self?.spawnBlackrockSpearman()
                }
            ]))
        }

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

    public func stopSceneCompletely() {
        removeAllActions()

        children.forEach { $0.removeAllActions() }
        removeAllChildren()

        bgmPlayer?.stop()
        bgmPlayer?.currentTime = 0
        bgmPlayer?.volume = 1.0
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutBackground()
    }

    // MARK: Bohban UI

    private var bohbanHealthBarBG = SKShapeNode()
    private var bohbanHealthBarFill = SKShapeNode()
    private var bohbanNameLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")

    func createBohbanHealthBar() {

        bohbanHealthBarBG.removeFromParent()
        bohbanHealthBarFill.removeFromParent()
        bohbanNameLabel.removeFromParent()

        let barWidth: CGFloat = 22
        let barHeight: CGFloat = size.height * 0.42
        let xPos = size.width - 60
        let yPos = size.height / 2

        let bgRect = CGRect(x: -barWidth/2, y: -barHeight/2, width: barWidth, height: barHeight)
        bohbanHealthBarBG = SKShapeNode(rect: bgRect, cornerRadius: 4)
        bohbanHealthBarBG.strokeColor = .white
        bohbanHealthBarBG.lineWidth = 4
        bohbanHealthBarBG.fillColor = .clear
        bohbanHealthBarBG.position = CGPoint(x: xPos, y: yPos)
        bohbanHealthBarBG.zPosition = 999
        addChild(bohbanHealthBarBG)

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

    // --------------------------------------------------------
    // MARK: Begin / world-specific spawns
    // --------------------------------------------------------

    private let blackrockLoopKey = "blackrockWaveLoop"
    
    private func startBlackrockWaveNode() {

        // Hard reset blackrock wave state so we always start clean
        lastUpdate = 0
        coinAccumulator = 0

        currentBlackrockWaveIndex = -1
        blackrockWaveInProgress = false

        // Optional but recommended: make sure no delayed wave actions are still queued
        removeAction(forKey: "blackrockWaveStart")

        setupBlackrockWaves()

        // Start wave 1 exactly once
        run(.sequence([
            .run { [weak self] in
                self?.startNextBlackrockWave()
            }
        ]), withKey: "blackrockWaveStart")

        bgmPlayer?.play()
    }

    
    public func begin() {
        guard !hasStarted, !isGameOver else { return }
        hasStarted = true
        startedSubject.send(())

        switch world {
        case .witheringTree:
            startScoringAndSpawns()          // ents / elves / druids ONLY here

        case .blackrockValley:
            startBlackrockWaveNode()         // Blackrock-only wave system

        default:
            bgmPlayer?.play()
        }
    }
    
    
    
    private func startNextBlackrockWave() {
        currentBlackrockWaveIndex += 1

        // All Blackrock waves done – for now just stop
        if currentBlackrockWaveIndex >= blackrockWaves.count {
            // later you can spawn a Blackrock boss here
            return
        }

        let config = blackrockWaves[currentBlackrockWaveIndex]
        blackrockWaveInProgress = true

        // Update the HUD (LEVEL / WAVE  X / 49 still works)
        waveSubject.send(currentBlackrockWaveIndex + 1)

        for _ in 0..<config.axeThrowers {
            spawnBlackrockAxeThrower()
        }
        
        for _ in 0..<config.shamans {
            spawnBlackrockShaman()
        }
        
        for _ in 0..<config.spearmen {
            spawnBlackrockSpearman()
        }
    }


    private func startBlackrockSpawns() {
        lastUpdate = 0
        coinAccumulator = 0
        bgmPlayer?.play()

        let spawn = SKAction.run { [weak self] in
            self?.spawnBlackrockAxeThrower()
        }
        let wait = SKAction.wait(forDuration: 6.0, withRange: 3.0)
        run(.repeatForever(.sequence([spawn, wait])), withKey: "blackrockSpawns")
    }

    // --------------------------------------------------------
    // MARK: Druid orb explosion FX
    // --------------------------------------------------------

    func showOrbExplosion(at p: CGPoint) {
        let explosion = SKEmitterNode()

        explosion.particleTexture = SKTexture(imageNamed: "pixel")
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

    // --------------------------------------------------------
    // MARK: Full reset
    // --------------------------------------------------------

    public func fullReset() {

        // Stop spawners/timers/actions
        isPaused = false
        removeAllActions()
        children.forEach { $0.removeAllActions() }
        removeAllChildren()

        // Rebuild background
        arenaBackground = nil
        buildBackgroundIfNeeded()
        layoutBackground()

        // Clear enemies / arrays
        ents.removeAll()
        woodlandElves.removeAll()
        woodlandDruids.removeAll()
        blackrockAxeThrowers.removeAll()
        blackrockShamans.removeAll()
        blackrockSpearmen.removeAll()

        // Boss cleanup
        bohban?.removeAllActions()
        bohban?.removeFromParent()
        bohban = nil

        bohbanHealthBarBG.removeFromParent()
        bohbanHealthBarFill.removeFromParent()
        bohbanNameLabel.removeFromParent()

        // Reset run state
        isGameOver = false
        hasStarted = false   // CRITICAL: allow begin() to run again

        coins = 0
        coinAccumulator = 0
        lastUpdate = 0
        lastFireTime = -1_000

        movementInput = .zero
        attackInput = .zero

        // Reset BOTH wave systems
        currentWaveIndex = -1
        waveInProgress = false
        currentBlackrockWaveIndex = -1
        blackrockWaveInProgress = false

        // Recreate core nodes (same as didMove)
        configureFingerNode()
        configureWizardNode()

        fingerNode.position = CGPoint(x: size.width * 0.5, y: size.height * 0.35)

        // Reset wizard visuals AFTER wizard node exists
        wizardPose = .front
        updateWizardTexture()

        // Reset HUD
        coinsSubject.send(0)
        waveSubject.send(1)

        // Music: stop old, rebuild fresh ONCE, rewind, but do not play here
        bgmPlayer?.stop()
        bgmPlayer = nil
        configureMusic()              // prepares player at time 0

        // Rebuild wave tables so begin() starts clean in either biome
        setupWaves()
        setupBlackrockWaves()
    }

    // Bohban spawn

    func spawnBohban() {
        if bohban != nil { return }

        let boss = BohbanNode(screenWidth: size.width, scene: self)
        bohban = boss

        addChild(boss)
        boss.runEntrance(in: self)
        createBohbanHealthBar()
    }

    // --------------------------------------------------------
    // MARK: Waves / Scoring
    // --------------------------------------------------------

    public func playLevelUpSound() {
        run(.playSoundFileNamed("levelUp.wav", waitForCompletion: false))
    }

    func playHealSound() {
        let action = SKAction.playSoundFileNamed("healingpotion.wav", waitForCompletion: false)
        run(action)
    }

    func playPowerUpSound() {
        let action = SKAction.playSoundFileNamed("powerUp.wav", waitForCompletion: false)
        run(action)
    }

    func playManaShieldHitSound() {
        let action = SKAction.playSoundFileNamed("manashieldhit.wav", waitForCompletion: false)
        run(action)
    }

    func playFairyDustSound() {
        let action = SKAction.playSoundFileNamed("fairydust.wav", waitForCompletion: false)
        run(action)

        let wizardWidth  = wizardNode.frame.width
        let wizardHeight = wizardNode.frame.height
        let wizardDiameter = max(wizardWidth, wizardHeight)

        let auraRadius = wizardDiameter * 13.8
        let aura = SKShapeNode(circleOfRadius: auraRadius)

        aura.fillColor = UIColor.yellow.withAlphaComponent(0.35)
        aura.strokeColor = UIColor.orange.withAlphaComponent(0.8)
        aura.lineWidth = 4
        aura.zPosition = 80
        aura.glowWidth = 12
        aura.blendMode = .add

        aura.position = .zero
        wizardNode.addChild(aura)

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

        if currentWaveIndex >= waves.count {
            return
        }

        let config = waves[currentWaveIndex]
        waveInProgress = true

        waveSubject.send(currentWaveIndex + 1)

        for _ in 0..<config.ents {
            spawnEnt()
        }

        for _ in 0..<config.elves {
            spawnWoodlandElf()
        }

        for _ in 0..<config.druids {
            spawnWoodlandDruid()
        }
    }

    private func setupWaves() {
        waves.removeAll()

        for wave in 1...49 {
            let entsCount  = min(1 + wave / 3, 12)
            let elvesCount = max(0, (wave - 4) / 3)

            var druidsCount = 0

            if playerLevelForSpawns >= 20 && wave >= 20 {
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
    
    private func setupBlackrockWaves() {
        blackrockWaves.removeAll()

        for wave in 1...49 {
            let axeCount = min(2 + wave / 2, 18)

            // Shamans: start at wave 5, then +1 every ~6 waves, cap at 4
            let shamanCount: Int
            if wave < 5 {
                shamanCount = 0
            } else {
                shamanCount = min(1 + (wave - 5) / 6, 4)
            }

            // Spearmen: start at wave 2, scale slowly, cap at 10
            let spearmanCount: Int
            if wave < 2 {
                spearmanCount = 0
            } else {
                spearmanCount = min(1 + (wave - 2) / 3, 10)
            }

            blackrockWaves.append(BlackrockWaveConfig(
                axeThrowers: axeCount,
                shamans: shamanCount,
                spearmen: spearmanCount
            ))
        }

        currentBlackrockWaveIndex = -1
        blackrockWaveInProgress = false
    }



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
                             y: size.height * 0.55)
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
    // MARK: Enemy spawn telegraph (veggies – unused)
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
    // MARK: BLACKROCK VALLEY ENEMIES
    // --------------------------------------------------------

    func spawnBlackrockSpearman() {
        guard !isGameOver else { return }

        let padding: CGFloat = 40
        let x = CGFloat.random(in: padding...(size.width - padding))

        let spearman = BlackrockSpearmanNode(
            startX: x,
            sceneHeight: size.height
        )

        addChild(spearman)
        blackrockSpearmen.append(spearman)
    }

    
    func spawnBlackrockShaman() {
        guard !isGameOver else { return }

        // Similar to druid: choose a side and a hover center
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
        default: // bottom-ish (avoid spawning too low)
            center = CGPoint(x: CGFloat.random(in: size.width * 0.2...size.width * 0.8),
                             y: size.height * 0.55)
        }

        let targetDiameter = fingerRadius * 5.0
        let shaman = BlackrockShamanNode(
            targetDiameter: targetDiameter,
            startCenter: center
        )
        addChild(shaman)
        blackrockShamans.append(shaman)
    }

    
    func spawnBlackrockAxeThrower() {
        guard !isGameOver else { return }

        let marginX: CGFloat = 40
        let spawnY = CGFloat.random(in: (size.height * 0.45)...(size.height * 0.8))
        let fromLeft = Bool.random()

        let direction: BlackrockAxeThrowerNode.Direction = fromLeft ? .fromLeft : .fromRight
        let spawnX: CGFloat
        let targetX: CGFloat

        if fromLeft {
            spawnX  = -marginX
            targetX = CGFloat.random(in: size.width * 0.22...size.width * 0.35)
        } else {
            spawnX = size.width + marginX
            targetX = CGFloat.random(in: size.width * 0.65...size.width * 0.78)
        }

        let targetDiameter = fingerRadius * 5.0
        let axeThrower = BlackrockAxeThrowerNode(
            targetDiameter: targetDiameter,
            direction: direction,
            targetX: targetX
        )
        axeThrower.position = CGPoint(x: spawnX, y: spawnY)
        addChild(axeThrower)
        blackrockAxeThrowers.append(axeThrower)
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
        body.contactTestBitMask = Cat.veggie | Cat.ent | Cat.elf | Cat.druid | Cat.shaman | Cat.spearman
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

        // cooldown tick
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

        // Blizzard DOT
        if isBlizzardActive {
            blizzardDamageAccumulator += dt

            while blizzardDamageAccumulator >= 0.2 {
                blizzardDamageAccumulator -= 0.2

                // ENT DAMAGE
                for ent in ents {
                    let died = ent.takeDamage(20)
                    if died { awardXP(20); entKillSubject.send(1) }
                    ent.speedMultiplier = blizzardSlowMultiplier
                }

                // ELF DAMAGE
                for elf in woodlandElves {
                    let died = elf.takeDamage(20)
                    if died { awardXP(15); elfKillSubject.send(1) }
                    elf.speedMultiplier = blizzardSlowMultiplier
                }

                // BLACKROCK AXE THROWER DAMAGE
                for axe in blackrockAxeThrowers {
                    let died = axe.takeDamage(20)
                    if died { awardXP(20); elfKillSubject.send(1) } // treat like elf for now
                    axe.speedMultiplier = blizzardSlowMultiplier
                }
                
                //BLACKROCK SHAMAN DAMANGE
                for shaman in blackrockShamans {
                    let died = shaman.takeDamage(20)
                    if died { awardXP(30); druidKillSubject.send(1) } // or make a shamanKillPublisher later
                    shaman.speedMultiplier = blizzardSlowMultiplier
                }

                // DRUID DAMAGE
                for druid in woodlandDruids {
                    let died = druid.takeDamage(20)
                    if died { awardXP(30); druidKillSubject.send(1) }
                    druid.speedMultiplier = blizzardSlowMultiplier
                }

                // BOHBAN DAMAGE
                if let boss = bohban, boss.parent != nil {
                    let died = boss.takeDamage(20)
                    updateBohbanHealthBar(currentHP: boss.hp, maxHP: 2000)
                    if died {
                        bohbanHealthBarBG.removeFromParent()
                        bohbanNameLabel.removeFromParent()
                    }
                }
            }
        }

        // Bohban update
        if let boss = bohban {
            let dtBoss = currentTime - lastBossUpdate
            lastBossUpdate = currentTime
            boss.update(dt: dtBoss, playerPosition: fingerNode.position, scene: self)
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

        // FIREBALL BOUNCING
        for node in children {
            guard let sprite = node as? SKSpriteNode else { continue }
            if sprite.texture?.description.contains("fireball") != true { continue }
            guard let body = sprite.physicsBody else { continue }

            var bounces = sprite.userData?["bounces"] as? Int ?? 0

            if sprite.position.x <= 20 || sprite.position.x >= size.width - 20 {
                body.velocity.dx = -body.velocity.dx
                bounces += 1
            }

            if sprite.position.y <= 20 || sprite.position.y >= size.height - 20 {
                body.velocity.dy = -body.velocity.dy
                bounces += 1
            }

            sprite.userData?["bounces"] = bounces

            if bounces >= 8 {
                sprite.run(.sequence([
                    .fadeOut(withDuration: 0.2),
                    .removeFromParent()
                ]))
            }
        }

        // Storm aura DOT
        if isStormAuraActive {
            stormAuraDamageAccumulator += dt

            while stormAuraDamageAccumulator >= 0.1 {
                stormAuraDamageAccumulator -= 0.1

                let auraRadius: CGFloat = 10
                let center = fingerNode.position

                // ENT
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

                // ELF
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

                // BLACKROCK AXE THROWER
                for axe in blackrockAxeThrowers {
                    guard axe.parent != nil else { continue }
                    let d = hypot(axe.position.x - center.x, axe.position.y - center.y)
                    if d <= auraRadius {
                        let died = axe.takeDamage(10)
                        if died {
                            awardXP(20)
                            elfKillSubject.send(1)
                        }
                    }
                }
                
                for shaman in blackrockShamans {
                    let d = hypot(shaman.position.x - center.x, shaman.position.y - center.y)
                    if d <= auraRadius {
                        let died = shaman.takeDamage(20)
                        if died { awardXP(30); druidKillSubject.send(1) }
                    }
                }

                // DRUID
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

                // BOHBAN
                if let boss = bohban, boss.parent != nil {
                    let d = hypot(boss.position.x - center.x, boss.position.y - center.y)
                    if d <= auraRadius {

                        let died = boss.takeDamage(25)
                        updateBohbanHealthBar(currentHP: boss.hp, maxHP: 2000)

                        if died {
                            bohbanHealthBarBG.removeFromParent()
                            bohbanNameLabel.removeFromParent()
                        }
                    }
                }
            }
        }

        // ICE BLOCK CONTACT DAMAGE
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

                // BLACKROCK AXE THROWER
                for axe in blackrockAxeThrowers {
                    let d = hypot(axe.position.x - center.x, axe.position.y - center.y)
                    if d <= radius {
                        let died = axe.takeDamage(20)
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

                // BOHBAN
                if let boss = bohban, boss.parent != nil {
                    let d = hypot(boss.position.x - center.x, boss.position.y - center.y)
                    if d <= radius {
                        let died = boss.takeDamage(20)
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

        // Update woodland elves
        for elf in woodlandElves {
            elf.update(dt: dt, playerPosition: fingerNode.position)
        }

        // Update druids
        for druid in woodlandDruids {
            druid.update(dt: dt, playerPosition: fingerNode.position)
        }

        // Update Blackrock axe throwers (only relevant in Blackrock Valley)
        if world == .blackrockValley {
            for axe in blackrockAxeThrowers {
                axe.update(dt: dt, playerPosition: fingerNode.position)
            }
            for shaman in blackrockShamans {
                shaman.update(dt: dt, playerPosition: fingerNode.position)
            }
            
        }


        // Auto-shoot from right analog
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
        if world == .witheringTree || world == .blackrockValley {
            coinAccumulator += dt
            while coinAccumulator >= 1 {
                coinAccumulator -= 1
                coins += 1
                coinsSubject.send(coins)
                SaveManager.shared.saveCoins(coins)
            }
        }


        cleanupOffscreen()
        ents.removeAll { $0.parent == nil }
        woodlandElves.removeAll { $0.parent == nil }
        woodlandDruids.removeAll { $0.parent == nil }
        blackrockAxeThrowers.removeAll { $0.parent == nil }
        blackrockShamans.removeAll { $0.parent == nil }
        blackrockSpearmen.removeAll { $0.parent == nil }

        // WITHERING TREE progression
        if world == .witheringTree,
           waveInProgress,
           ents.isEmpty,
           woodlandElves.isEmpty,
           woodlandDruids.isEmpty {

            waveInProgress = false

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

        // BLACKROCK VALLEY progression
        if world == .blackrockValley,
           blackrockWaveInProgress,
           blackrockAxeThrowers.isEmpty,
           blackrockShamans.isEmpty,
           blackrockSpearmen.isEmpty {

            blackrockWaveInProgress = false

            run(.sequence([
                .wait(forDuration: 2.0),
                .run { [weak self] in self?.startNextBlackrockWave() }
            ]))
        }
    }

    func startBohbanBossFight() {

        if let bg = arenaBackground {
            bg.texture = SKTexture(imageNamed: "bohbanarena")
            bg.texture?.filteringMode = .nearest
            layoutBackground()
        }

        bgmPlayer?.stop()

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

        bohban = BohbanNode(screenWidth: size.width, scene: self)
        bohban = BohbanNode(screenWidth: size.width, scene: self)
        if let b = bohban {
            addChild(b)
            createBohbanHealthBar()
            b.runEntrance(in: self)

            b.onBossDeath = { [weak self] in
                self?.handleBohbanDefeat()
            }
        }

    }

    func onBohbanDeath() {
        bgmPlayer?.setVolume(0.0, fadeDuration: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.bgmPlayer?.stop()
            self.bgmPlayer = nil
        }

        bgmPlayer = nil

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

        attackSpeedMultiplier = savedAttackMultiplier

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

        guard trySpendMana(15) else {
            run(.playSoundFileNamed("notenoughmana.wav", waitForCompletion: false))
            return
        }
        guard isSpellReady("fireball") else { return }

        let dx = movementInput.dx
        let dy = movementInput.dy
        let mag = hypot(dx, dy)

        let ux: CGFloat
        let uy: CGFloat

        if mag < 0.2 {
            ux = 0
            uy = 1
        } else {
            ux = dx / mag
            uy = dy / mag
        }

        spawnFireball(ux: ux, uy: uy)
    }

    private func spawnFireball(ux: CGFloat, uy: CGFloat) {

        let speed: CGFloat = 520
        let fireballSize: CGFloat = 42

        let fb = SKSpriteNode(imageNamed: "fireball")
        fb.zPosition = 100
        fb.position = fingerNode.position
        fb.setScale(fireballSize / max(fb.size.width, fb.size.height))
        fb.blendMode = .add
        fb.alpha = 0.95

        fb.userData = ["bounces": 0]

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

        savedMovementVector = movementInput
        savedAttackMultiplier = attackSpeedMultiplier

        guard trySpendMana(35) else { return }
        guard isSpellReady("iceblock") else { return }

        movementInput = .zero
        attackInput = .zero
        attackSpeedMultiplier = 0

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
        blizzardSlowMultiplier = 0.75
        addChild(blizzardNodeContainer)

        guard trySpendMana(50) else { return }
        guard isSpellReady("blizzard") else { return }

        let oldTexture = wizardNode.texture
        wizardNode.texture = SKTexture(imageNamed: "wizardspell")
        wizardNode.texture?.filteringMode = .nearest

        run(.sequence([
            .wait(forDuration: 10.0),
            .run { [weak self] in
                self?.stopBlizzard()
                self?.wizardNode.texture = oldTexture
            }
        ]))

        spawnBlizzardBolts()
    }

    private func dropOneBlizzardBolt() {
        guard isBlizzardActive else { return }

        let xPos = CGFloat.random(in: size.width * 0.1 ... size.width * 0.9)
        let startY = size.height + 40

        let bolt = SKSpriteNode(imageNamed: "blizzardbolt")
        bolt.zPosition = 90
        bolt.alpha = 0.92
        bolt.blendMode = .add
        bolt.setScale(0.05)

        bolt.position = CGPoint(x: xPos, y: startY)
        blizzardNodeContainer.addChild(bolt)

        let glowUp = SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        let glowDown = SKAction.fadeAlpha(to: 0.85, duration: 0.1)
        bolt.run(.repeatForever(.sequence([glowUp, glowDown])))

        let fall = SKAction.moveBy(x: 0, y: -size.height - 80, duration: 1.15)
        bolt.run(.sequence([fall, .removeFromParent()]))
    }

    private func spawnBlizzardBolts() {
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

        removeAction(forKey: "BlizzardBoltSpawner")

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
            bubble.alpha = 0.85

            wizardNode.addChild(bubble)
            bubble.position = .zero

            var wizardWidth  = wizardNode.frame.width
            var wizardHeight = wizardNode.frame.height

            if wizardWidth < 10 || wizardHeight < 10 {
                wizardWidth  = fingerRadius * 2.0
                wizardHeight = fingerRadius * 2.0
            }

            let wizardDiameter = max(wizardWidth, wizardHeight)
            let bubbleDiameter = wizardDiameter * 10.8

            let baseBubbleSize = max(bubble.size.width, bubble.size.height)
            let scale = bubbleDiameter / max(baseBubbleSize, 1)

            bubble.setScale(scale)

            manaShieldNode = bubble

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
        removeAction(forKey: "RapidWandTimer")

        isRapidWandActive = true
        attackSpeedMultiplier = 1.5
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
        guard !isStormAuraActive else { return }

        setStormAura(active: true)
        playLightningSpellSound()

        run(.sequence([
            .wait(forDuration: 10.0),
            .run { [weak self] in self?.setStormAura(active: false) }
        ]))
    }

    func setStormAura(active: Bool) {
        if active {
            guard stormAuraNode == nil else { return }

            let aura = SKSpriteNode(imageNamed: "lightningshieldeffect")
            aura.zPosition = 60
            aura.alpha = 0.9
            aura.blendMode = .add

            let w = wizardNode.frame.width
            let h = wizardNode.frame.height
            let wizardDiameter = max(w, h)

            let auraDiameter = wizardDiameter * 13.0
            let baseSize = max(aura.size.width, aura.size.height)
            let scale = auraDiameter / max(baseSize, 1)
            aura.setScale(scale)

            wizardNode.addChild(aura)
            aura.position = .zero

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

    // XP Gain
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
               cat == Cat.druidOrb ||
               cat == Cat.shamanrock
            {

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

        // Bohban Damage
        if mask == (Cat.missile | Cat.druid) {
            let bossBody = (a.categoryBitMask == Cat.druid) ? a : b
            let missileBody = (bossBody == a) ? b : a

            if let bohban = bossBody.node as? BohbanNode {
                let died = bohban.takeDamage(10)
                missileBody.node?.removeFromParent()

                if died {
                    bohbanHealthBarBG.removeFromParent()
                    bohbanNameLabel.removeFromParent()
                }
            }
        }

        // FIREBALL HIT (strong projectile)
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

            if let fb = fireballBody.node as? SKSpriteNode,
               fb.texture?.description.contains("fireball") == true {

                if let ent = enemyBody.node as? EntNode {
                    let died = ent.takeDamage(50)
                    if died { awardXP(25); entKillSubject.send(1) }
                }

                if let elf = enemyBody.node as? WoodlandElfNode {
                    let died = elf.takeDamage(50)
                    if died { awardXP(20); elfKillSubject.send(1) }
                }

                if let axe = enemyBody.node as? BlackrockAxeThrowerNode {
                    let died = axe.takeDamage(50)
                    if died { awardXP(20); elfKillSubject.send(1) }
                }

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

                showHitPop(at: fireballBody.node!.position)
                return
            }
        }

        // Player hit by ENT
        if mask == (Cat.finger | Cat.ent) {
            let entBody = (a.categoryBitMask == Cat.ent) ? a : b
            if let ent = entBody.node as? EntNode {
                ent.explode()
            }

            if isStormAuraActive || isIceBlockActive {
                return
            }

            damageSubject.send(25)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }
        
        //Player hit by shaman rock
        if mask == (Cat.finger | Cat.shamanrock) {
            let rockBody = (a.categoryBitMask == Cat.shamanrock) ? a : b
            rockBody.node?.removeFromParent()

            if isStormAuraActive || isIceBlockActive {
                return
            }

            damageSubject.send(35)
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
                    awardXP(25)
                    entKillSubject.send(1)
                }
            }

            missileBody.node?.removeFromParent()

            let hitPoint = contact.contactPoint
            showHitPop(at: hitPoint)
            return
        }
        
        // Missile hits Shaman
        if mask == (Cat.missile | Cat.shaman) {
            let shamanBody: SKPhysicsBody
            let missileBody: SKPhysicsBody

            if a.categoryBitMask == Cat.shaman {
                shamanBody = a
                missileBody = b
            } else {
                shamanBody = b
                missileBody = a
            }

            if let shaman = shamanBody.node as? BlackrockShamanNode {
                let died = shaman.takeDamage(10)
                if died { awardXP(30); druidKillSubject.send(1) }
            }

            missileBody.node?.removeFromParent()
            showHitPop(at: contact.contactPoint)
            return
        }
        
        // Missle hits spearman
        
        if mask == (Cat.missile | Cat.spearman) {
            let enemyBody: SKPhysicsBody
            let missileBody: SKPhysicsBody

            if a.categoryBitMask == Cat.spearman {
                enemyBody = a
                missileBody = b
            } else {
                enemyBody = b
                missileBody = a
            }

            if let spear = enemyBody.node as? BlackrockSpearmanNode {
                let died = spear.takeDamage(10)
                if died { awardXP(20); elfKillSubject.send(1) } // or make a spearmanKill publisher later
            }

            missileBody.node?.removeFromParent()
            showHitPop(at: contact.contactPoint)
            return
        }



        // Missile hits woodland elf OR Blackrock axe thrower
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
                    awardXP(20)
                    elfKillSubject.send(1)
                }
            } else if let axe = elfBody.node as? BlackrockAxeThrowerNode {
                let died = axe.takeDamage(10)
                if died {
                    awardXP(20)
                    elfKillSubject.send(1)
                }
            }

            missileBody.node?.removeFromParent()
            let hitPoint = contact.contactPoint
            showHitPop(at: hitPoint)
            return
        }

        // Player hit by elf arrow / boomerang axe
        if mask == (Cat.finger | Cat.elfArrow) {
            let arrowBody = (a.categoryBitMask == Cat.elfArrow) ? a : b
            arrowBody.node?.removeFromParent()

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
                    awardXP(40)
                    druidKillSubject.send(1)
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

        // If we're resetting, these may already be parented somewhere.
        fingerNode.removeFromParent()
        fingerNode.removeAllActions()

        // Physics (fresh each time)
        let body = SKPhysicsBody(circleOfRadius: fingerRadius)
        body.isDynamic = false
        body.categoryBitMask = Cat.finger
        body.collisionBitMask = 0
        body.contactTestBitMask =
            Cat.veggie |
            Cat.ent |
            Cat.elfArrow |
            Cat.druidOrb |
            Cat.shamanrock |
            Cat.elf |
            Cat.druid |
            Cat.shaman

        fingerNode.physicsBody = body
        fingerNode.zPosition = 40
        addChild(fingerNode)

        // Ring: detach before re-adding
        fingerRing.removeFromParent()
        fingerRing.removeAllActions()
        fingerRing.lineWidth = 2
        fingerRing.alpha = 0.15
        fingerNode.addChild(fingerRing)

        // Trail: remove old emitter so you don't stack them
        trailEmitter?.removeFromParent()
        trailEmitter = nil

        let dot = makeCircleTexture(diameter: 5, color: .white)
        let trail = makeTrail(texture: dot)
        trailEmitter = trail
        fingerNode.addChild(trail)
    }

    private func configureWizardNode() {

        // If we're resetting, the previous wizard sprite is still attached to fingerNode.
        wizardNode?.removeFromParent()
        wizardNode?.removeAllActions()

        let tex = SKTexture(imageNamed: "wizardforward")
        tex.filteringMode = .nearest

        let newWizard = SKSpriteNode(texture: tex)
        newWizard.zPosition = 50

        let desiredDiameter = fingerRadius * 2.0
        wizardBaseScale = desiredDiameter / max(tex.size().width, tex.size().height)
        newWizard.setScale(wizardBaseScale)

        fingerNode.addChild(newWizard)
        wizardNode = newWizard
    }


    private func refreshWizardPose() {
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

        let textureName: String
        switch world {
        case .witheringTree:
            textureName = "witheringforest"
        case .blackrockValley:
            textureName = "blackrockvalleymap"
        default:
            textureName = "witheringforest"
        }

        let bg = SKSpriteNode(imageNamed: textureName)
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
        } catch {
            print("Audio session error:", error)
        }

        let resourceName: String
        switch world {
        case .blackrockValley:
            resourceName = "blackrockvalleytheme"
        default:
            resourceName = "Battle"
        }

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            print("Could not find BGM resource:", resourceName)
            return
        }

        // If we already have a player:
        // - Stop it (prevents overlap)
        // - If it's the same track, just rewind and keep it
        if let existing = bgmPlayer {
            existing.stop()

            // If same file, rewind and reuse
            if let existingURL = existing.url, existingURL == url {
                existing.currentTime = 0
                existing.volume = 1.0
                existing.numberOfLoops = -1
                existing.prepareToPlay()
                bgmPlayer = existing
                return
            } else {
                // Different track (world change) -> discard and recreate
                bgmPlayer = nil
            }
        }

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
