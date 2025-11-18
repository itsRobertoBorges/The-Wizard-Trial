//
//  WoodlandDruidNode.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2025-11-16.
//

import SpriteKit

final class WoodlandDruidNode: SKSpriteNode {

    private enum State {
        case idle
        case casting
        case dead
    }

    // MARK: - Stats / behavior

    let maxHP: Int = 60
    private(set) var hp: Int = 60

    private var state: State = .idle

    // hovering path
    private var hoverCenter: CGPoint
    private var hoverRadius: CGFloat = 26
    private var hoverAngle: CGFloat = 0
    private let hoverSpeed: CGFloat = 1.6      // radians per second

    // shooting
    private var timeSinceLastShot: TimeInterval = 0
    private let shootInterval: TimeInterval = 5.0

    // animation frames
    private var idleTexture: SKTexture
    private var castTexture: SKTexture

    // MARK: - Init

    init(targetDiameter: CGFloat, startCenter: CGPoint) {
        self.hoverCenter = startCenter

        // Load spritesheet named exactly "woodland druid"
        let sheet = SKTexture(imageNamed: "woodlanddruid")
        sheet.filteringMode = .nearest

        // 1 row, 2 columns (0 = float, 1 = cast)
        let rows = 1
        let cols = 2
        let frameWidth  = 1.0 / CGFloat(cols)
        let frameHeight = 1.0 / CGFloat(rows)

        // first frame
        let idleRect = CGRect(
            x: 0 * frameWidth,
            y: 0,
            width: frameWidth,
            height: frameHeight
        )
        let castRect = CGRect(
            x: 1 * frameWidth,
            y: 0,
            width: frameWidth,
            height: frameHeight
        )

        let idleTex = SKTexture(rect: idleRect, in: sheet)
        let castTex = SKTexture(rect: castRect, in: sheet)
        idleTex.filteringMode = .nearest
        castTex.filteringMode = .nearest

        self.idleTexture = idleTex
        self.castTexture = castTex

        super.init(texture: idleTex, color: .clear, size: idleTex.size())

        name = "woodlandDruid"
        zPosition = 8

        // scale to requested size
        let baseSize = max(idleTex.size().width, idleTex.size().height)
        let scale = targetDiameter / baseSize
        setScale(scale)

        position = startCenter
        hoverCenter = startCenter

        setupPhysics()
        startIdleHoverAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Physics

    private func setupPhysics() {
        let body = SKPhysicsBody(circleOfRadius: max(size.width, size.height) * 0.35)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false

        body.categoryBitMask = Cat.druid
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.missile  // missiles can hit him
        physicsBody = body
    }

    // MARK: - Hover animation

    private func startIdleHoverAnimation() {
        // simple up-down bob to make him feel floaty
        let up  = SKAction.moveBy(x: 0, y: 6, duration: 0.6)
        let down = SKAction.moveBy(x: 0, y: -6, duration: 0.6)
        up.timingMode = .easeInEaseOut
        down.timingMode = .easeInEaseOut
        let bob = SKAction.repeatForever(.sequence([up, down]))
        run(bob, withKey: "hoverBob")
    }

    // optionally allow GameScene to adjust center if needed
    func setHoverCenter(_ p: CGPoint) {
        hoverCenter = p
    }

    // MARK: - Public update

    func update(dt: TimeInterval, playerPosition: CGPoint) {
        guard state != .dead else { return }

        // 1) Hover in a little sideways circle
        hoverAngle += hoverSpeed * CGFloat(dt)
        let offsetX = cos(hoverAngle) * hoverRadius
        let offsetY = sin(hoverAngle) * hoverRadius * 0.5 // ellipse
        position = CGPoint(x: hoverCenter.x + offsetX,
                           y: hoverCenter.y + offsetY)

        // 2) Shooting timer
        timeSinceLastShot += dt
        if timeSinceLastShot >= shootInterval, state == .idle {
            castAndShoot(at: playerPosition)
        }
    }

    // MARK: - Casting / shooting

    private func castAndShoot(at target: CGPoint) {
        guard state != .dead else { return }
        state = .casting
        timeSinceLastShot = 0

        // swap texture to casting pose
        texture = castTexture

        // small scale up for drama
        let scaleUp = SKAction.scale(to: xScale * 1.08, duration: 0.12)
        let hold    = SKAction.wait(forDuration: 0.12)
        let scaleDown = SKAction.scale(to: xScale, duration: 0.1)

        // after a short delay, spawn orb
        let spawn = SKAction.run { [weak self] in
            guard let self else { return }
            self.spawnOrb(toward: target)
        }

        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            self.texture = self.idleTexture
            self.state = .idle
        }

        let seq = SKAction.sequence([
            scaleUp,
            spawn,
            hold,
            scaleDown,
            finish
        ])

        run(seq, withKey: "cast")
    }

    private func spawnOrb(toward target: CGPoint) {
        guard let scene = self.scene else { return }

        let orb = SKNode()
        orb.zPosition = 9

        // big green/black glowing ball
        let r: CGFloat = 26

        let core = SKShapeNode(circleOfRadius: r * 0.55)
        core.fillColor = .black
        core.strokeColor = .clear
        core.zPosition = 1
        orb.addChild(core)

        let glow = SKShapeNode(circleOfRadius: r)
        glow.fillColor = UIColor.systemGreen.withAlphaComponent(0.4)
        glow.strokeColor = UIColor.systemGreen.withAlphaComponent(0.9)
        glow.lineWidth = 2
        glow.glowWidth = 10
        glow.zPosition = 0
        orb.addChild(glow)

        // little pulsing scale
        let up = SKAction.scale(to: 1.12, duration: 0.25)
        let down = SKAction.scale(to: 0.95, duration: 0.25)
        orb.run(.repeatForever(.sequence([up, down])))

        // physics
        let body = SKPhysicsBody(circleOfRadius: r)
        body.isDynamic = true
        body.affectedByGravity = false
        body.categoryBitMask = Cat.druidOrb
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.finger
        body.linearDamping = 0
        orb.physicsBody = body

        orb.position = position
        scene.addChild(orb)

        // aim at player position at cast time (no tracking)
        let dx = target.x - orb.position.x
        let dy = target.y - orb.position.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len
        let uy = dy / len

        let speed: CGFloat = 260
        body.velocity = CGVector(dx: ux * speed, dy: uy * speed)

        orb.run(.sequence([
            .wait(forDuration: 5.0),
            .removeFromParent()
        ]))
    }

    // MARK: - Damage / death

    @discardableResult
    func takeDamage(_ amount: Int) -> Bool {
        guard state != .dead else { return false }

        hp -= amount

        // quick flash
        let flash = SKAction.sequence([
            .colorize(with: .systemGreen, colorBlendFactor: 0.9, duration: 0.08),
            .colorize(withColorBlendFactor: 0.0, duration: 0.15)
        ])
        run(flash)

        if hp <= 0 {
            die()
            return true
        }
        return false
    }

    private func die() {
        state = .dead
        removeAllActions()

        let scaleOut = SKAction.scale(to: xScale * 1.4, duration: 0.18)
        let fadeOut  = SKAction.fadeOut(withDuration: 0.18)
        let remove   = SKAction.removeFromParent()

        run(.sequence([.group([scaleOut, fadeOut]), remove]))
    }
}
