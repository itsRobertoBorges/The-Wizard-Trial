import SpriteKit

final class BlackrockSpearmanNode: SKSpriteNode {

    // MARK: - Config
    private let moveSpeed: CGFloat = 420   // points per second
    private let animFPS: Double = 8        // tweak as desired

    // MARK: - Textures
    private static let atlasTexture: SKTexture = {
        let t = SKTexture(imageNamed: "orcspear")
        t.filteringMode = .nearest
        return t
    }()

    private static let walkFrames: [SKTexture] = {
        // 1 row, 2 columns
        let cols: CGFloat = 2
        let frameW = 1.0 / cols
        let frameH = 1.0

        // SpriteKit rects are normalized, origin at bottom-left
        let rect0 = CGRect(x: 0.0 * frameW, y: 0.0, width: frameW, height: frameH)
        let rect1 = CGRect(x: 1.0 * frameW, y: 0.0, width: frameW, height: frameH)

        let f0 = SKTexture(rect: rect0, in: atlasTexture)
        let f1 = SKTexture(rect: rect1, in: atlasTexture)

        f0.filteringMode = .nearest
        f1.filteringMode = .nearest

        return [f0, f1]
    }()
    
    // Physics
    
    let maxHP: Int = 60
    private(set) var hp: Int = 60

    private func configurePhysics() {
        let body = SKPhysicsBody(circleOfRadius: max(size.width, size.height) * 0.18)
        body.isDynamic = true
        body.affectedByGravity = false
        body.categoryBitMask = Cat.spearman
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.missile | Cat.finger
        body.linearDamping = 0
        physicsBody = body
    }

    func takeDamage(_ amount: Int) -> Bool {
        hp -= amount
        if hp <= 0 {
            die()
            return true
        }
        return false
    }

    private func die() {
        removeAllActions()
        physicsBody = nil
        run(.sequence([
            .fadeOut(withDuration: 0.12),
            .removeFromParent()
        ]))
    }


    // MARK: - Init
    init(startX: CGFloat, sceneHeight: CGFloat) {
        let first = Self.walkFrames[0]
        super.init(texture: first, color: .clear, size: first.size())

        name = "BlackrockSpearman"

        // Spawn slightly above screen
        position = CGPoint(
            x: startX,
            y: sceneHeight + size.height
        )

        zPosition = 10
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        let desiredDiameter: CGFloat = 260  
        let base = max(size.width, size.height)
        let scale = desiredDiameter / max(base, 1)
        setScale(scale)

        startWalkAnimation()
        startMovingDown(sceneHeight: sceneHeight)
        configurePhysics()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Animation
    private func startWalkAnimation() {
        let frameTime = 1.0 / animFPS
        let animate = SKAction.animate(with: Self.walkFrames, timePerFrame: frameTime, resize: false, restore: false)
        run(SKAction.repeatForever(animate), withKey: "walk")
    }

    // MARK: - Movement
    private func startMovingDown(sceneHeight: CGFloat) {
        // Go well past the bottom edge
        let endY: CGFloat = -200   // or -size.height, but fixed is safer
        let distance = position.y - endY
        let duration = TimeInterval(distance / moveSpeed)

        let moveDown = SKAction.moveTo(y: endY, duration: duration)
        moveDown.timingMode = .linear

        run(.sequence([moveDown, .removeFromParent()]), withKey: "moveDown")
    }

}
