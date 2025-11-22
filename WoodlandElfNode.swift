import SpriteKit

final class WoodlandElfNode: SKSpriteNode {

    enum Direction {
        case fromLeft
        case fromRight
    }

    private enum State {
        case walking
        case idle
        case shooting
        case dead
    }

    // MARK: - Stats
    let maxHP: Int = 50
    private(set) var hp: Int = 50

    // MARK: - Movement / behavior
    private let direction: Direction
    private let targetX: CGFloat
    private var state: State = .walking
    var speedMultiplier: CGFloat = 1.0


    private let moveSpeed: CGFloat = 120
    private let shootInterval: TimeInterval = 4.0
    private var timeSinceLastShot: TimeInterval = 0

    // MARK: - Animation
    private var allFrames: [SKTexture] = []
    private var walkFrames: [SKTexture] = []
    private var shootPose: SKTexture?    // 6th frame
    private let walkActionKey  = "woodlandElfWalk"
    private let shootActionKey = "woodlandElfShoot"

    // MARK: - Init

    init(targetDiameter: CGFloat, direction: Direction, targetX: CGFloat) {
        self.direction = direction
        self.targetX   = targetX

        let sheet = SKTexture(imageNamed: "woodlandelf")
        sheet.filteringMode = .nearest

        // woodlandelf is 1 row x 6 columns (32x32 each)
        let rows = 1
        let cols = 6
        let frameWidth  = 1.0 / CGFloat(cols)
        let frameHeight = 1.0 / CGFloat(rows)

        var frames: [SKTexture] = []
        for col in 0..<cols {
            let rect = CGRect(
                x: CGFloat(col) * frameWidth,
                y: 0.0,
                width: frameWidth,
                height: frameHeight
            )
            let tex = SKTexture(rect: rect, in: sheet)
            tex.filteringMode = .nearest
            frames.append(tex)
        }
        self.allFrames = frames

        // Frames 0–3 walk, frame 5 (last) = shooting pose
        if frames.count >= 6 {
            self.walkFrames = Array(frames[0..<4])
            self.shootPose  = frames[5]
        } else {
            self.walkFrames = frames
            self.shootPose  = frames.last
        }

        let startTexture = self.walkFrames.first ?? sheet
        super.init(texture: startTexture, color: .clear, size: startTexture.size())

        name = "woodlandElf"
        zPosition = 20
        
        // Scale to targetDiameter
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
        physicsBody?.categoryBitMask = Cat.elf
        physicsBody?.collisionBitMask = 0
        physicsBody?.contactTestBitMask = Cat.missile | Cat.finger
    }
    
    // Health
    
    class EnemyNode: SKSpriteNode {

        var maxHP: Int = 100
        var currentHP: Int = 100

        private var hpBarBackground: SKSpriteNode!
        private var hpBarFill: SKSpriteNode!

        func setupHealthBar() {
            let barWidth: CGFloat = size.width * 0.8
            let barHeight: CGFloat = 4

            // Background outline (white)
            hpBarBackground = SKSpriteNode(color: .white, size: CGSize(width: barWidth, height: barHeight))
            hpBarBackground.position = CGPoint(x: 0, y: size.height / 2 + 10)
            hpBarBackground.zPosition = 500
            addChild(hpBarBackground)

            // Fill (green)
            hpBarFill = SKSpriteNode(color: .green, size: CGSize(width: barWidth - 2, height: barHeight - 2))
            hpBarFill.position = CGPoint.zero
            hpBarFill.zPosition = 501
            hpBarBackground.addChild(hpBarFill)
        }

        func updateHealthBar() {
            let ratio = CGFloat(currentHP) / CGFloat(maxHP)
            let fullWidth = hpBarBackground.size.width - 2

            hpBarFill.size.width = fullWidth * ratio

            // Green → Red transition like RuneScape
            if ratio > 0.66 {
                hpBarFill.color = .green
            } else if ratio > 0.33 {
                hpBarFill.color = .yellow
            } else {
                hpBarFill.color = .red
            }
        }

        // Call this whenever taking damage
        func takeDamage(_ dmg: Int) -> Bool {
            currentHP = max(currentHP - dmg, 0)
            updateHealthBar()
            return currentHP == 0
        }
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
        if let shootPose = shootPose {
            texture = shootPose
        } else if let last = walkFrames.last {
            texture = last
        }
    }

    // MARK: - Public update

    func update(dt: TimeInterval, playerPosition: CGPoint) {
        guard state != .dead else { return }

        // Movement
        if state == .walking {
            let dirSign: CGFloat = (direction == .fromLeft) ? 1.0 : -1.0
            position.x += dirSign * moveSpeed * CGFloat(dt)

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

        // Shooting timer
        timeSinceLastShot += dt
        if state != .dead,
           state != .walking,
           timeSinceLastShot >= shootInterval {
            shoot(at: playerPosition)
        }
    }

    // MARK: - Shooting

    private func shoot(at target: CGPoint) {
        guard state != .dead else { return }
        state = .shooting
        timeSinceLastShot = 0

        // Freeze on shooting pose
        if let shootPose = shootPose {
            texture = shootPose
        }

        spawnArrow(toward: target)

        let wait = SKAction.wait(forDuration: 0.12)
        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            self.state = .idle
            self.holdAtReadyPose()
        }
        run(.sequence([wait, finish]), withKey: shootActionKey)
    }

    private func spawnArrow(toward target: CGPoint) {
        guard let scene = self.scene else { return }

        // === 1) Build a procedural "necrotic" arrow node ===
        let arrowNode = SKNode()
        arrowNode.zPosition = 40

        // Shaft
        let shaftWidth: CGFloat = 6
        let shaftLength: CGFloat = 32
        let shaftRect = CGRect(x: -shaftWidth / 2, y: -shaftLength / 2, width: shaftWidth, height: shaftLength)
        let shaft = SKShapeNode(rect: shaftRect, cornerRadius: 3)
        shaft.fillColor = .systemPurple
        shaft.strokeColor = .white
        shaft.lineWidth = 1.5
        shaft.glowWidth = 3
        shaft.zPosition = 1
        arrowNode.addChild(shaft)

        // Arrowhead (triangle at top)
        let headPath = UIBezierPath()
        headPath.move(to: CGPoint(x: 0, y: shaftLength / 2 + 4))
        headPath.addLine(to: CGPoint(x: -10, y: shaftLength / 2 - 4))
        headPath.addLine(to: CGPoint(x: 10, y: shaftLength / 2 - 4))
        headPath.close()

        let head = SKShapeNode(path: headPath.cgPath)
        head.fillColor = .systemGreen
        head.strokeColor = .white
        head.lineWidth = 1.5
        head.glowWidth = 3
        head.zPosition = 2
        arrowNode.addChild(head)

        // Necrotic trail “energy”
        let auraRadius: CGFloat = 18
        let aura = SKShapeNode(circleOfRadius: auraRadius)
        aura.fillColor = UIColor.systemGreen.withAlphaComponent(0.25)
        aura.strokeColor = UIColor.systemPurple.withAlphaComponent(0.7)
        aura.lineWidth = 1
        aura.glowWidth = 6
        aura.zPosition = -1
        arrowNode.addChild(aura)

        // Little pulsing scale so it feels alive
        let pulseUp   = SKAction.scale(to: 1.15, duration: 0.25)
        let pulseDown = SKAction.scale(to: 0.9, duration: 0.25)
        arrowNode.run(.repeatForever(.sequence([pulseUp, pulseDown])))

        // === 2) Physics setup ===
        let r = max(shaftLength, auraRadius * 2) / 2
        let body = SKPhysicsBody(circleOfRadius: r)
        body.isDynamic = true
        body.affectedByGravity = false
        body.categoryBitMask = Cat.elfArrow
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.finger
        body.linearDamping = 0
        arrowNode.physicsBody = body

        // === 3) Spawn position (slightly above the elf) ===
        arrowNode.position = CGPoint(x: position.x, y: position.y + 4)
        scene.addChild(arrowNode)

        // === 4) Direction at fire time ===
        let dx = target.x - arrowNode.position.x
        let dy = target.y - arrowNode.position.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len
        let uy = dy / len

        // Rotate so the arrow’s "north" points toward the player
        let angle = atan2(uy, ux) - .pi / 2
        arrowNode.zRotation = angle

        // === 5) Velocity ===
        let speed: CGFloat = 360
        body.velocity = CGVector(dx: ux * speed, dy: uy * speed)

        // === 6) Auto-remove after a bit ===
        arrowNode.run(.sequence([
            .wait(forDuration: 4.0),
            .removeFromParent()
        ]))
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
