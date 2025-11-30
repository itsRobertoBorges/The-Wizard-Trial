//
//  BohbanNode.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2025-11-22.
//

import SpriteKit
import AVFoundation

final class BohbanNode: SKSpriteNode {
    
    //on death
    var onBossDeath: (() -> Void)?
    
    //Reference to GameScene
    private weak var gameScene: GameScene?
    
    // Audio player (for alternative manual control)
    private var roarPlayer: AVAudioPlayer?

    // =========================================================
    // MARK: - Stats
    // =========================================================
    private(set) var hp: Int = 2000
    private let attackInterval: TimeInterval = 2.5
    private var timeSinceLastAttack: TimeInterval = 0

    // =========================================================
    // MARK: - Textures
    // =========================================================
    private var entranceTexture: SKTexture!
    private var bounceTexture: SKTexture!
    private var attackTexture: SKTexture!
    private var roarTexture: SKTexture!

    // =========================================================
    // MARK: - Init
    // =========================================================
    init(screenWidth: CGFloat, scene: GameScene) {
        
        self.gameScene = scene

        entranceTexture = SKTexture(imageNamed: "bobahn")
        bounceTexture   = SKTexture(imageNamed: "bobahnbounce")
        attackTexture   = SKTexture(imageNamed: "bobahnattack")
        roarTexture     = SKTexture(imageNamed: "bobahnroar")

        entranceTexture.filteringMode = .nearest
        bounceTexture.filteringMode   = .nearest
        attackTexture.filteringMode   = .nearest
        roarTexture.filteringMode     = .nearest

        super.init(texture: entranceTexture, color: .clear, size: entranceTexture.size())
        
        self.setScale(0.25)
        self.zPosition = 500

        setupPhysics()
        startRoarLoop()
    }

    required init?(coder: NSCoder) { fatalError() }

    // =========================================================
    // MARK: - Physics
    // =========================================================
    private func setupPhysics() {
        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 0.5,
                                                        height: size.height * 0.5))
        physicsBody?.isDynamic = false
        physicsBody?.categoryBitMask = Cat.druid
        physicsBody?.collisionBitMask = 0
        physicsBody?.contactTestBitMask = Cat.missile
    }

    // =========================================================
    // MARK: - Entrance Animation
    // =========================================================
    func runEntrance(in scene: SKScene) {

        self.texture = entranceTexture
        self.alpha = 0

        let startY = scene.size.height + size.height * 0.5
        let targetY = scene.size.height * 0.65

        self.position = CGPoint(x: scene.size.width / 2, y: startY)

        let fadeIn = SKAction.fadeIn(withDuration: 0.9)
        let descend = SKAction.moveTo(y: targetY, duration: 2.2)
        descend.timingMode = .easeOut

        let stopAndIdle = SKAction.run { [weak self] in
            self?.texture = self?.bounceTexture
        }

        run(.sequence([fadeIn, descend, stopAndIdle]))
    }

    // =========================================================
    // MARK: - Update (attacks)
    // =========================================================
    func update(dt: TimeInterval, playerPosition: CGPoint, scene: SKScene) {
        timeSinceLastAttack += dt

        if timeSinceLastAttack >= attackInterval {
            timeSinceLastAttack = 0
            performAttack(toward: playerPosition, scene: scene)
        }
    }

    private func performAttack(toward target: CGPoint, scene: SKScene) {
        self.texture = attackTexture

        run(.sequence([
            .wait(forDuration: 0.4),
            .run { [weak self] in self?.texture = self?.bounceTexture }
        ]))

        fireProjectile(toward: target, scene: scene)
    }

    // =========================================================
    // MARK: - Roar Loop (every 10 sec)
    // =========================================================
    
    private func playRoarSound() {
        guard let url = Bundle.main.url(forResource: "bobahnroar", withExtension: "wav") else {
            print("ERROR: bobahnroar.wav not found")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 3.5    // 🔊 Increase if needed
            player.prepareToPlay()
            player.play()

            roarPlayer = player   // keep strong reference so it doesn’t get destroyed
        } catch {
            print("ROAR SOUND ERROR:", error)
        }
    }

    
    private func startRoarLoop() {

        let roarAction = SKAction.run { [weak self] in
            guard let self = self else { return }

            // Show roar sprite
            self.texture = self.roarTexture
            
            // Play roar audio
            self.playRoarSound()

            // === DELAY BEFORE SUMMONING ===
            self.run(.sequence([
                .wait(forDuration: 2.0),   // ⏳ wait 2 seconds
                SKAction.run { [weak self] in
                    guard let self = self else { return }

                    // Summon minions AFTER delay
                    self.gameScene?.spawnEnt()
                    self.gameScene?.spawnWoodlandDruid()
                    self.gameScene?.spawnWoodlandDruid()
                }
            ]))

            // Return to bounce pose (keep short)
            self.run(.sequence([
                .wait(forDuration: 0.6),
                .run { [weak self] in self?.texture = self?.bounceTexture }
            ]))
        }

        let loop = SKAction.repeatForever(.sequence([
            .wait(forDuration: 10.0),
            roarAction
        ]))

        run(loop, withKey: "roarLoop")
    }


    // =========================================================
    // MARK: - Projectile
    // =========================================================
    private func fireProjectile(toward target: CGPoint, scene: SKScene) {

        let radius: CGFloat = 18
        let orb = SKShapeNode(circleOfRadius: radius)

        orb.fillColor = UIColor.green.withAlphaComponent(0.85)
        orb.strokeColor = UIColor.white.withAlphaComponent(0.9)
        orb.lineWidth = 3
        orb.glowWidth = 7
        orb.zPosition = 300
        orb.name = "bohbanOrb"

        orb.position = self.position

        // Pulse animation
        let pulse = SKAction.repeatForever(.sequence([
            .scale(to: 1.25, duration: 0.25),
            .scale(to: 1.0, duration: 0.25)
        ]))
        orb.run(pulse)

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.isDynamic = true
        body.affectedByGravity = false
        body.linearDamping = 0
        body.categoryBitMask = Cat.druidOrb
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.finger
        orb.physicsBody = body

        // Snapshot aim
        let dx = target.x - orb.position.x
        let dy = target.y - orb.position.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len
        let uy = dy / len

        body.velocity = CGVector(dx: ux * 420, dy: uy * 420)

        // Trail emitter
        orb.addChild(makeOrbTrail())
        scene.addChild(orb)

        // Cleanup
        orb.run(.repeatForever(.sequence([
            .wait(forDuration: 0.1),
            .run { [weak orb, weak scene] in
                guard let orb = orb, let scene = scene else { return }
                let pad: CGFloat = 40
                if orb.position.x < -pad ||
                    orb.position.x > scene.size.width + pad ||
                    orb.position.y < -pad ||
                    orb.position.y > scene.size.height + pad {
                    orb.removeFromParent()
                }
            }
        ])))
    }

    // =========================================================
    // MARK: - Trail + Explosion
    // =========================================================
    private func makePixelTexture(color: UIColor = .white) -> SKTexture {
        let size = CGSize(width: 1, height: 1)
        UIGraphicsBeginImageContext(size)
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return SKTexture(image: img)
    }

    private func makeOrbTrail() -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = makePixelTexture(color: .white)
        e.particleBirthRate = 180
        e.particleLifetime = 0.35
        e.particleAlpha = 0.9
        e.particleAlphaSpeed = -2
        e.particleScale = 5
        e.particleScaleSpeed = -5
        e.particleColor = .green
        e.particleColorBlendFactor = 1
        e.particleSpeed = 10
        e.particleSpeedRange = 20
        e.particlePositionRange = CGVector(dx: 4, dy: 4)
        e.particleBlendMode = .add
        return e
    }

    func showExplosion(at position: CGPoint, scene: SKScene) {
        let sprite = SKSpriteNode(imageNamed: "bohbanexplode")
        sprite.position = position
        sprite.zPosition = 999
        sprite.setScale(0.35)
        sprite.name = "bohbanExplosion"

        scene.addChild(sprite)

        sprite.run(.sequence([
            .scale(to: 1.3, duration: 0.12),
            .fadeOut(withDuration: 0.22),
            .removeFromParent()
        ]))
    }

    // =========================================================
    // MARK: - Damage & Death
    // =========================================================
    func takeDamage(_ amount: Int) -> Bool {
        hp -= amount
        
        // Tell GameScene to update the bar
        gameScene?.updateBohbanHealthBar(currentHP: hp, maxHP: 2000)

        if hp <= 0 {
            die()
            return true
        }
        return false
    }


    private func die() {
        removeAction(forKey: "float")
        removeAction(forKey: "roarLoop")

        let fade = SKAction.fadeOut(withDuration: 0.4)
        let remove = SKAction.removeFromParent()

        run(.sequence([fade, remove, .run { [weak self] in
            self?.onBossDeath?()
        }]))
    }

}
