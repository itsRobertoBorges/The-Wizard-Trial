//
//  BlackrockShamanNode.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2026-01-09.
//

import SpriteKit

final class BlackrockShamanNode: SKSpriteNode {

    private enum State {
        case idle
        case casting
        case dead
    }

    // MARK: - Stats / behavior

    let maxHP: Int = 80
    private(set) var hp: Int = 80

    private var state: State = .idle

    // Hovering path
    private var hoverCenter: CGPoint
    private var hoverRadius: CGFloat = 26
    private var hoverAngle: CGFloat = 0
    private let hoverSpeed: CGFloat = 1.6      // radians/sec
    var speedMultiplier: CGFloat = 1.0

    // Casting
    private var timeSinceLastCast: TimeInterval = 0
    private let castInterval: TimeInterval = 5.0

    // Animation frames (1 row, 2 cols)
    private var idleTexture: SKTexture
    private var castTexture: SKTexture

    // MARK: - Init

    init(targetDiameter: CGFloat, startCenter: CGPoint) {
        self.hoverCenter = startCenter

        // Spritesheet named exactly "BlackrockShaman"
        let sheet = SKTexture(imageNamed: "BlackrockShaman")
        sheet.filteringMode = .nearest

        let rows = 1
        let cols = 2
        let frameWidth  = 1.0 / CGFloat(cols)
        let frameHeight = 1.0 / CGFloat(rows)

        let idleRect = CGRect(x: 0 * frameWidth, y: 0, width: frameWidth, height: frameHeight)
        let castRect = CGRect(x: 1 * frameWidth, y: 0, width: frameWidth, height: frameHeight)

        let idleTex = SKTexture(rect: idleRect, in: sheet)
        let castTex = SKTexture(rect: castRect, in: sheet)
        idleTex.filteringMode = .nearest
        castTex.filteringMode = .nearest

        self.idleTexture = idleTex
        self.castTexture = castTex

        super.init(texture: idleTex, color: .clear, size: idleTex.size())

        name = "blackrockShaman"
        zPosition = 8

        // Scale to requested size
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

        // TODO: Update these to match your project’s categories
        body.categoryBitMask = Cat.shaman
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.missile

        physicsBody = body
    }

    // MARK: - Hover animation

    private func startIdleHoverAnimation() {
        let up  = SKAction.moveBy(x: 0, y: 6, duration: 0.6)
        let down = SKAction.moveBy(x: 0, y: -6, duration: 0.6)
        up.timingMode = .easeInEaseOut
        down.timingMode = .easeInEaseOut
        run(.repeatForever(.sequence([up, down])), withKey: "hoverBob")
    }

    func setHoverCenter(_ p: CGPoint) {
        hoverCenter = p
    }

    // MARK: - Update

    func update(dt: TimeInterval, playerPosition: CGPoint) {
        guard state != .dead else { return }

        // Hover ellipse
        hoverAngle += hoverSpeed * CGFloat(dt) * speedMultiplier
        let offsetX = cos(hoverAngle) * hoverRadius
        let offsetY = sin(hoverAngle) * hoverRadius * 0.5
        position = CGPoint(x: hoverCenter.x + offsetX,
                           y: hoverCenter.y + offsetY)

        // Cast timer
        timeSinceLastCast += dt
        if timeSinceLastCast >= castInterval, state == .idle {
            castRockfall(at: playerPosition)
        }
    }

    // MARK: - Casting

    private func castRockfall(at target: CGPoint) {
        guard state != .dead else { return }
        state = .casting
        timeSinceLastCast = 0

        texture = castTexture

        let scaleUp = SKAction.scale(to: xScale * 1.08, duration: 0.12)
        let hold    = SKAction.wait(forDuration: 0.12)
        let scaleDown = SKAction.scale(to: xScale, duration: 0.1)

        let spawn = SKAction.run { [weak self] in
            self?.spawnFallingRock(above: target)
        }

        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            self.texture = self.idleTexture
            self.state = .idle
        }

        run(.sequence([scaleUp, spawn, hold, scaleDown, finish]), withKey: "cast")
    }

    /// Spawns a rock above the target and drops it straight down.
    private func spawnFallingRock(above target: CGPoint) {
        guard let scene = self.scene else { return }

        // If you have a rock sprite asset, use it:
        // let rock = SKSpriteNode(texture: SKTexture(imageNamed: "sandstone_rock"))
        // rock.texture?.filteringMode = .nearest

        // Otherwise, placeholder circle
        let rock = SKShapeNode(circleOfRadius: 18)
        rock.fillColor = .brown
        rock.strokeColor = .clear

        rock.zPosition = 9
        rock.position = CGPoint(x: target.x, y: target.y + 520) // spawn above screen-ish
        scene.addChild(rock)

        // Physics
        let body = SKPhysicsBody(circleOfRadius: 18)
        body.isDynamic = true
        body.affectedByGravity = false
        body.linearDamping = 0

        // TODO: Update categories
        body.categoryBitMask = Cat.shamanRock
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.player | Cat.finger

        rock.physicsBody = body

        // Straight down velocity
        let fallSpeed: CGFloat = 520
        body.velocity = CGVector(dx: 0, dy: -fallSpeed)

        // Cleanup
        rock.run(.sequence([
            .wait(forDuration: 2.5),
            .removeFromParent()
        ]))
    }

    // MARK: - Damage / death

    @discardableResult
    func takeDamage(_ amount: Int) -> Bool {
        guard state != .dead else { return false }

        hp -= amount

        let flash = SKAction.sequence([
            .colorize(with: .red, colorBlendFactor: 0.85, duration: 0.08),
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
        run(.sequence([.group([scaleOut, fadeOut]), .removeFromParent()]))
    }
}
