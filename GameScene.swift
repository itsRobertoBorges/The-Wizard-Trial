import SpriteKit
import UIKit
import Combine
import AVFoundation

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
    
    // --------------------------------------------------------
    // MARK: Waves
    // --------------------------------------------------------

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

    override func didMove(to view: SKView) {
        buildBackgroundIfNeeded()
        layoutBackground()

        backgroundColor = .black
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        view.isMultipleTouchEnabled = true

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

    override func didChangeSize(_ oldSize: CGSize) {
        layoutBackground()
    }

    // --------------------------------------------------------
    // MARK: Public API for SwiftUI
    // --------------------------------------------------------

    public func begin() {
        guard !hasStarted, !isGameOver else { return }
        hasStarted = true
        startedSubject.send(())
        startScoringAndSpawns()
    }
    
    public func fullReset() {
        removeAllActions()

        children
            .filter {
                let cat = $0.physicsBody?.categoryBitMask
                return cat == Cat.veggie ||
                       cat == Cat.missile ||
                       cat == Cat.ent ||
                       cat == Cat.elf ||
                       cat == Cat.elfArrow ||
                       cat == Cat.druid ||
                       cat == Cat.druidOrb
            }
            .forEach { $0.removeFromParent() }

        ents.removeAll()
        woodlandElves.removeAll()
        woodlandDruids.removeAll()

        isGameOver = false
        hasStarted = false
        coins = 0
        coinAccumulator = 0
        lastUpdate = 0

        wizardPose = .front
        updateWizardTexture()

        coinsSubject.send(0)
        waveSubject.send(1)      // reset wave display

        bgmPlayer?.stop()
        bgmPlayer?.currentTime = 0
        bgmPlayer?.volume = 1.0

        // reset waves
        setupWaves()
    }

    //Woodland boss (later)
//    if currentWaveIndex >= waves.count {
//        // All 49 waves complete → boss time
//        spawnBoss()
//        return
//    }

    // --------------------------------------------------------
    // MARK: Waves / Spawning + scoring
    // --------------------------------------------------------

    //level up sound
    public func playLevelUpSound() {
           run(.playSoundFileNamed("levelUp.wav", waitForCompletion: false))
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

    private func spawnWoodlandDruid() {
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

    private func showWizardCast(
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

    private func spawnEnt() {
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

    private func spawnWoodlandElf() {
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
        if now - lastFireTime < minFireInterval { return }
        lastFireTime = now

        run(.playSoundFileNamed("autoattacksound.mp3", waitForCompletion: false))

        let start = fingerNode.position
        let dx = target.x - start.x
        let dy = target.y - start.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len
        let uy = dy / len

        let r: CGFloat = 8
        let missile = SKSpriteNode(imageNamed: "autoshoot")
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

        let dt = min(currentTime - lastUpdate, 1/30)
        lastUpdate = currentTime

        // Movement
        let step = moveSpeed * CGFloat(dt)
        fingerNode.position.x += movementInput.dx * step
        fingerNode.position.y += movementInput.dy * step

        // Bounds
        let margin: CGFloat = 40
        fingerNode.position.x = max(margin, min(size.width - margin, fingerNode.position.x))
        fingerNode.position.y = max(margin, min(size.height - margin, fingerNode.position.y))

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
        }

        cleanupOffscreen()
        ents.removeAll { $0.parent == nil }
        woodlandElves.removeAll { $0.parent == nil }
        woodlandDruids.removeAll { $0.parent == nil }
        
        // Wave completion check
        if waveInProgress &&
           ents.isEmpty &&
           woodlandElves.isEmpty {

            waveInProgress = false

            // Small breather before next wave
            let wait = SKAction.wait(forDuration: 2.0)
            let next = SKAction.run { [weak self] in
                self?.startNextWave()
            }
            run(.sequence([wait, next]))
        }
    }
    
    // XP Gainz
    private func awardXP(_ amount: Int) {
        xpSubject.send(amount)
    }

    private func cleanupOffscreen() {
        let pad: CGFloat = 100
        for node in children {
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

        // Player hit by veggie (if you ever bring them back)
        if mask == (Cat.finger | Cat.veggie) {
            if a.categoryBitMask == Cat.veggie { a.node?.removeFromParent() }
            if b.categoryBitMask == Cat.veggie { b.node?.removeFromParent() }

            damageSubject.send(10)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }

        // Player hit by ENT → explode + 25 damage
        if mask == (Cat.finger | Cat.ent) {
            let entBody = (a.categoryBitMask == Cat.ent) ? a : b
            if let ent = entBody.node as? EntNode {
                ent.explode()
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

            damageSubject.send(15)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }

        // Player hit by druid orb
        if mask == (Cat.finger | Cat.druidOrb) {
            let orbBody = (a.categoryBitMask == Cat.druidOrb) ? a : b
            orbBody.node?.removeFromParent()

            damageSubject.send(35) // big hit
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

    public func triggerGameOver() {
        handleGameOver()
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
        var dx = p.x - center.x
        var dy = p.y - center.y
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
