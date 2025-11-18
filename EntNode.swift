import SpriteKit

final class EntNode: SKSpriteNode {

    // Simple HP
    var maxHP: Int = 100
    var hp: Int = 100

    // Walk animation
    private var walkFrames: [SKTexture] = []
    private let walkActionKey = "entWalk"

    // MARK: - Init matching GameScene (targetDiameter:)
    init(targetDiameter: CGFloat) {
        // Make sure your sheet is named "ent" in Assets
        let sheet = SKTexture(imageNamed: "ent")
        sheet.filteringMode = .nearest

        // 2 rows × 3 columns
        let rows = 2
        let cols = 3

        let frameWidth  = 1.0 / CGFloat(cols)
        let frameHeight = 1.0 / CGFloat(rows)

        walkFrames.removeAll()

        // Use the TOP row of the sheet (row index 1 in SpriteKit UV space)
        let walkRow = 1

        // 🔹 epsilon to avoid sampling neighbour pixels (prevents that tiny line)
        let epsilon: CGFloat = 0.002

        for col in 0..<cols {
            let u = CGFloat(col) * frameWidth
            let v = CGFloat(walkRow) * frameHeight

            let rect = CGRect(
                x: u + epsilon,
                y: v + epsilon,
                width: frameWidth  - 2 * epsilon,
                height: frameHeight - 2 * epsilon
            )

            let tex = SKTexture(rect: rect, in: sheet)
            tex.filteringMode = .nearest
            walkFrames.append(tex)
        }

        let startTexture = walkFrames.first ?? sheet
        super.init(texture: startTexture, color: .clear, size: startTexture.size())

        name = "ent"
        zPosition = 5

        // Scale him relative to the wizard/finger radius
        let baseSize = max(startTexture.size().width, startTexture.size().height)
        let scale = (targetDiameter * 1.6) / baseSize   // bump this up/down for size
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

    // MARK: - Animation
    private func startWalking() {
        guard !walkFrames.isEmpty else { return }
        if action(forKey: walkActionKey) != nil { return }

        let animate = SKAction.animate(
            with: walkFrames,
            timePerFrame: 0.12,
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
