//
//  BlackrockAxeThrowerNode.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2025-12-02.
//


import SpriteKit

final class BlackrockAxeThrowerNode: SKSpriteNode {

    enum Direction {
        case fromLeft
        case fromRight
    }

    private enum State {
        case walking
        case idle
        case throwing
        case dead
    }

    // MARK: - Stats
    let maxHP: Int = 60
    private(set) var hp: Int = 60

    // MARK: - Movement / behavior
    private let direction: Direction
    private let targetX: CGFloat
    private var state: State = .walking
    var speedMultiplier: CGFloat = 1.0

    private let moveSpeed: CGFloat = 120
    private let throwInterval: TimeInterval = 3.0
    private var timeSinceLastThrow: TimeInterval = 0

    // MARK: - Animation
    private var allFrames: [SKTexture] = []
    private var walkFrames: [SKTexture] = []
    private var throwPose: SKTexture?    // last frame with axe
    private let walkActionKey  = "blackrockWalk"
    private let throwActionKey = "blackrockThrow"

    // MARK: - Init

    init(targetDiameter: CGFloat, direction: Direction, targetX: CGFloat) {
        self.direction = direction
        self.targetX   = targetX

        // Full spritesheet texture (1 row, 6 columns)
        let sheet = SKTexture(imageNamed: "blackrockvalleyaxethrower")
        sheet.filteringMode = .nearest

        let cols = 3  
        let frameWidth = 1.0 / CGFloat(cols)
        let frameHeight: CGFloat = 1.0   // single row

        var frames: [SKTexture] = []
        for col in 0..<cols {
            let x = CGFloat(col) * frameWidth
            let rect = CGRect(x: x,
                              y: 0.0,
                              width: frameWidth,
                              height: frameHeight)
            let tex = SKTexture(rect: rect, in: sheet)
            tex.filteringMode = .nearest
            frames.append(tex)
        }

        self.allFrames = frames

        // First 4 frames = walk, last frame = throw pose
        if frames.count >= 5 {
            self.walkFrames = Array(frames[0..<4])
            self.throwPose  = frames.last
        } else {
            self.walkFrames = frames
            self.throwPose  = frames.last
        }

        let startTexture = self.walkFrames.first ?? sheet
        super.init(texture: startTexture, color: .clear, size: startTexture.size())

        name = "blackrockAxeThrower"
        zPosition = 20

        // Scale to match elf size
        let baseSize = max(startTexture.size().width, startTexture.size().height)
        let scale = targetDiameter / baseSize
        setScale(scale)

        // Face the correct direction
        if direction == .fromRight {
            xScale = -abs(xScale) // face left
        } else {
            xScale =  abs(xScale) // face right
        }

        setupPhysics()
        startWalking()
    }


    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Physics

    private func setupPhysics() {
        physicsBody = SKPhysicsBody(rectangleOf: size)
        physicsBody?.affectedByGravity = false
        physicsBody?.allowsRotation = false

        // Re-use ELF category so existing damage code works
        physicsBody?.categoryBitMask = Cat.elf
        physicsBody?.collisionBitMask = 0
        physicsBody?.contactTestBitMask = Cat.missile | Cat.finger
    }

    // MARK: - Animation control

    private func startWalking() {
        guard !walkFrames.isEmpty else { return }
        removeAction(forKey: walkActionKey)

        let anim = SKAction.animate(
            with: walkFrames,
            timePerFrame: 0.12,
            resize: false,
            restore: false
        )
        run(.repeatForever(anim), withKey: walkActionKey)
    }

    private func holdAtReadyPose() {
        if let throwPose = throwPose {
            texture = throwPose
        } else if let last = walkFrames.last {
            texture = last
        }
    }

    // MARK: - Public update

    func update(dt: TimeInterval, playerPosition: CGPoint) {
        guard state != .dead else { return }

        // Movement into position
        if state == .walking {
            let dirSign: CGFloat = (direction == .fromLeft) ? 1.0 : -1.0
            position.x += dirSign * moveSpeed * speedMultiplier * CGFloat(dt)

            switch direction {
            case .fromLeft:
                if position.x >= targetX {
                    state = .idle
                    removeAction(forKey: walkActionKey)
                    holdAtReadyPose()
                }
            case .fromRight:
                if position.x <= targetX {
                    state = .idle
                    removeAction(forKey: walkActionKey)
                    holdAtReadyPose()
                }
            }
        }

        // Throw timer
        timeSinceLastThrow += dt
        if state != .dead,
           state != .walking,
           timeSinceLastThrow >= throwInterval {
            throwAxe(at: playerPosition)
        }
    }

    // MARK: - Throwing

    private func throwAxe(at target: CGPoint) {
        guard state != .dead else { return }
        state = .throwing
        timeSinceLastThrow = 0

        // Freeze on throw pose
        if let throwPose = throwPose {
            texture = throwPose
        }

        spawnBoomerang(toward: target)

        let wait = SKAction.wait(forDuration: 0.2)
        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            self.state = .idle
            self.holdAtReadyPose()
        }
        run(.sequence([wait, finish]), withKey: throwActionKey)
    }

    private func spawnBoomerang(toward target: CGPoint) {
        guard let scene = self.scene else { return }

        // Match the old grey ball size (radius 14 => diameter 28)
        let axeRadius: CGFloat = 30
        let targetDiameter: CGFloat = axeRadius * 4

        // Axe sprite
        let axeTexture = SKTexture(imageNamed: "axesprite")
        axeTexture.filteringMode = .nearest

        let axe = SKSpriteNode(texture: axeTexture)
        axe.name = "blackrockAxe"
        axe.zPosition = 30

        let origin = CGPoint(x: position.x, y: position.y + 4)
        axe.position = origin

        // Scale sprite so its largest dimension matches the old projectile diameter
        let scale = targetDiameter / max(axe.size.width, axe.size.height)
        axe.setScale(scale)

        // Physics: keep identical hitbox behavior to the old grey ball
        let body = SKPhysicsBody(circleOfRadius: axeRadius)
        body.isDynamic = true
        body.affectedByGravity = false
        body.categoryBitMask = Cat.elfArrow
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.finger
        body.linearDamping = 0
        axe.physicsBody = body

        scene.addChild(axe)

        // Boomerang path: out to player's position at throw time, then back
        let outDuration: TimeInterval = 0.45
        let backDuration: TimeInterval = 0.45

        let out = SKAction.move(to: target, duration: outDuration)
        let back = SKAction.move(to: origin, duration: backDuration)
        let remove = SKAction.removeFromParent()

        // Rotation (boomerang spin)
        let spin = SKAction.rotate(byAngle: .pi * 2, duration: 0.15)
        let spinForever = SKAction.repeatForever(spin)

        // Run movement and rotation together
        let path = SKAction.sequence([out, back, remove])
        axe.run(.group([path, spinForever]))
    }


    // MARK: - Damage / death

    @discardableResult
    func takeDamage(_ amount: Int) -> Bool {
        guard state != .dead else { return false }

        hp -= amount
        if hp <= 0 {
            die()
            return true
        }
        return false
    }

    private func die() {
        state = .dead
        removeAllActions()

        let sound = SKAction.playSoundFileNamed("explosion", waitForCompletion: false)
        let scaleUp = SKAction.scale(to: xScale * 1.3, duration: 0.08)
        let fadeOut = SKAction.fadeOut(withDuration: 0.2)
        let remove  = SKAction.removeFromParent()

        run(.sequence([sound, .group([scaleUp, fadeOut]), remove]))
    }
}
