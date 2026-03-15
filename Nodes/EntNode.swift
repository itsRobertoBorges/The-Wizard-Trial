import SpriteKit

final class EntNode: SKSpriteNode {

    enum Kind {
        case forestEnt
        case undeadKnight

        var sheetName: String {
            switch self {
            case .forestEnt:
                return "ent"
            case .undeadKnight:
                return "undead_knightwalk"
            }
        }

        var nodeName: String {
            switch self {
            case .forestEnt:
                return "ent"
            case .undeadKnight:
                return "undeadKnight"
            }
        }

        var scaleMultiplier: CGFloat {
            switch self {
            case .forestEnt:
                return 1.6
            case .undeadKnight:
                return 1.8
            }
        }

        var walkFrameTime: TimeInterval {
            switch self {
            case .forestEnt:
                return 0.12
            case .undeadKnight:
                return 0.10
            }
        }
    }
    
    var speedMultiplier: CGFloat = 1.0
    let kind: Kind
    

    // Simple HP
    var maxHP: Int = 100
    var hp: Int = 100

    // Walk animation
    private var walkFrames: [SKTexture] = []
    private let walkActionKey = "entWalk"

    // MARK: - Init matching GameScene (targetDiameter:)
    init(targetDiameter: CGFloat, kind: Kind = .forestEnt) {
        self.kind = kind

        let sheet = SKTexture(imageNamed: kind.sheetName)
        sheet.filteringMode = .nearest

        walkFrames.removeAll()
        let epsilon: CGFloat = 0.002

        switch kind {
        case .forestEnt:
            let rows = 2
            let cols = 3
            let frameWidth = 1.0 / CGFloat(cols)
            let frameHeight = 1.0 / CGFloat(rows)
            let walkRow = 1

            for col in 0..<cols {
                let u = CGFloat(col) * frameWidth
                let v = CGFloat(walkRow) * frameHeight
                let rect = CGRect(
                    x: u + epsilon,
                    y: v + epsilon,
                    width: frameWidth - 2 * epsilon,
                    height: frameHeight - 2 * epsilon
                )

                let tex = SKTexture(rect: rect, in: sheet)
                tex.filteringMode = .nearest
                walkFrames.append(tex)
            }

        case .undeadKnight:
            let cols = 6
            let frameWidth = 1.0 / CGFloat(cols)
            // The sprite sheet has a single visible row with a large transparent band
            // above and below, so crop the occupied vertical region only.
            let visibleBand = CGRect(x: 0, y: 0.18, width: 1.0, height: 0.54)

            for col in 0..<cols {
                let u = CGFloat(col) * frameWidth
                let rect = CGRect(
                    x: u + epsilon,
                    y: visibleBand.minY + epsilon,
                    width: frameWidth - 2 * epsilon,
                    height: visibleBand.height - 2 * epsilon
                )

                let tex = SKTexture(rect: rect, in: sheet)
                tex.filteringMode = .nearest
                walkFrames.append(tex)
            }
        }

        let startTexture = walkFrames.first ?? sheet
        super.init(texture: startTexture, color: .clear, size: startTexture.size())

        name = kind.nodeName
        zPosition = 5

        // Scale him relative to the wizard/finger radius
        let baseSize = max(startTexture.size().width, startTexture.size().height)
        let scale = (targetDiameter * kind.scaleMultiplier) / baseSize
        setScale(scale)

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

        physicsBody?.categoryBitMask = Cat.ent
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


    // MARK: - Animation
    private func startWalking() {
        guard !walkFrames.isEmpty else { return }
        if action(forKey: walkActionKey) != nil { return }

        let animate = SKAction.animate(
            with: walkFrames,
            timePerFrame: kind.walkFrameTime,
            resize: false,
            restore: false
        )
        let forever = SKAction.repeatForever(animate)
        run(forever, withKey: walkActionKey)
    }

    func stopWalking() {
        removeAction(forKey: walkActionKey)
        if let first = walkFrames.first {
            texture = first
        }
    }

    // MARK: - Damage / Death

    @discardableResult
    func takeDamage(_ amount: Int) -> Bool {
        hp -= amount
        if hp <= 0 {
            explode()
            return true
        }
        return false
    }

    @discardableResult
    func takeDamage(damage amount: Int) -> Bool {
        return takeDamage(amount)
    }

    func explode() {
        run(.playSoundFileNamed("explosion.wav", waitForCompletion: false))

        let scaleUp = SKAction.scale(to: xScale * 1.3, duration: 0.08)
        let fadeOut = SKAction.fadeOut(withDuration: 0.18)
        let remove  = SKAction.removeFromParent()
        let seq = SKAction.sequence([.group([scaleUp, fadeOut]), remove])
        run(seq)
    }
}
