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

    // Animation frames (idle/cast)
    private var idleTexture: SKTexture
    private var castTexture: SKTexture

    // MARK: - Init

    init(targetDiameter: CGFloat, startCenter: CGPoint) {
        self.hoverCenter = startCenter

        // Textures named exactly "orcshaman" and "orcshaman_cast"
        let idleTex = SKTexture(imageNamed: "orcshaman")
        let castTex = SKTexture(imageNamed: "orcshaman_cast")

        idleTex.filteringMode = .nearest
        castTex.filteringMode = .nearest

        self.idleTexture = idleTex
        self.castTexture = castTex

        super.init(texture: idleTex, color: .clear, size: idleTex.size())

        name = "orcshaman"
        zPosition = 8

        // Scale to requested size (slightly bigger so he reads as a higher-tier enemy)
        let baseSize = max(idleTex.size().width, idleTex.size().height)
        let scale = (targetDiameter / baseSize) * 1.15
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

        hoverAngle += hoverSpeed * CGFloat(dt) * speedMultiplier
        let offsetX = cos(hoverAngle) * hoverRadius
        let offsetY = sin(hoverAngle) * hoverRadius * 0.5
        position = CGPoint(
            x: hoverCenter.x + offsetX,
            y: hoverCenter.y + offsetY
        )

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
        let hold = SKAction.wait(forDuration: 0.12)
        let scaleDown = SKAction.scale(to: xScale, duration: 0.1)

        // MULTI-ROCK ONLY
        let spawn = SKAction.run { [weak self] in
            self?.spawnRockfall(at: target)
        }

        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            self.texture = self.idleTexture
            self.state = .idle
        }

        run(.sequence([scaleUp, spawn, hold, scaleDown, finish]), withKey: "cast")
    }

    // MARK: - Multi-rock fall (no single rock behavior)

    private func spawnRockfall(at target: CGPoint) {
        guard let scene = self.scene else { return }

        let rockTex = SKTexture(imageNamed: "shamanrock")
        rockTex.filteringMode = .nearest

        // Tuning knobs
        let rockCount = Int.random(in: 6...10)
        let spreadX: CGFloat = 120
        let spawnHeight: CGFloat = 520
        let fallSpeed: CGFloat = 520
        let rockDiameter: CGFloat = 36
        let delayStep: TimeInterval = 0.06

        for i in 0..<rockCount {
            let dx = CGFloat.random(in: -spreadX...spreadX)
            let spawnPos = CGPoint(x: target.x + dx, y: target.y + spawnHeight)

            let delay = SKAction.wait(forDuration: TimeInterval(i) * delayStep)
            let spawnOne = SKAction.run {
                let rock = SKSpriteNode(texture: rockTex)
                rock.zPosition = 9
                rock.size = CGSize(width: rockDiameter, height: rockDiameter)
                rock.position = spawnPos
                scene.addChild(rock)

                let body = SKPhysicsBody(circleOfRadius: rockDiameter * 0.5)
                body.isDynamic = true
                body.affectedByGravity = false
                body.linearDamping = 0
                body.categoryBitMask = Cat.shamanrock
                body.collisionBitMask = 0
                body.contactTestBitMask = Cat.finger
                rock.physicsBody = body

                body.velocity = CGVector(dx: 0, dy: -fallSpeed)

                rock.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 0.6)))
                rock.run(.sequence([
                    .wait(forDuration: 2.5),
                    .removeFromParent()
                ]))
            }

            // run the delayed spawn sequence on the shaman
            run(.sequence([delay, spawnOne]))
        }
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
