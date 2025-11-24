import SpriteKit

final class BohbanNode: SKSpriteNode {

    // ====== Stats ======
    private(set) var hp: Int = 2000
    private let moveSpeed: CGFloat = 120
    private let attackInterval: TimeInterval = 2.5
    private var timeSinceLastAttack: TimeInterval = 0

    // ====== Animation Frames ======
    private var animFrames: [SKTexture] = []

    // ====== Initialization ======
    init(screenWidth: CGFloat) {

        // Load sprite sheet (4 frames vertically)
        let sheet = SKTexture(imageNamed: "bohban")
        sheet.filteringMode = .nearest

        let frameHeight = sheet.size().height / 4
        let frameWidth = sheet.size().width

        var frames: [SKTexture] = []
        for i in 0..<4 {
            let rect = CGRect(
                x: 0,
                y: CGFloat(3 - i) * (frameHeight / sheet.size().height),
                width: 1.0,
                height: frameHeight / sheet.size().height
            )
            let tex = SKTexture(rect: rect, in: sheet)
            tex.filteringMode = .nearest
            frames.append(tex)
        }

        self.animFrames = frames

        let tex = animFrames.first!
        super.init(texture: tex, color: .clear, size: tex.size())

        self.setScale(3.8)
        self.zPosition = 500

        // Start bobbing + animation
        startFloatingMovement(screenWidth: screenWidth)
        startIdleAnimation()

        setupPhysics()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // ====== Physics ======
    private func setupPhysics() {
        physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: size.width * 0.5,
                                                        height: size.height * 0.5))
        physicsBody?.isDynamic = false
        physicsBody?.categoryBitMask = Cat.druid  // or make a new category Cat.boss
        physicsBody?.collisionBitMask = 0
        physicsBody?.contactTestBitMask = Cat.missile
    }

    // ====== Animation ======
    private func startIdleAnimation() {
        let action = SKAction.animate(with: animFrames, timePerFrame: 0.18)
        run(.repeatForever(action))
    }

    // ====== Movement ======
    private func startFloatingMovement(screenWidth: CGFloat) {
        let leftX: CGFloat = screenWidth * 0.15
        let rightX: CGFloat = screenWidth * 0.85

        let moveLeft = SKAction.moveTo(x: leftX, duration: 3.0)
        let moveRight = SKAction.moveTo(x: rightX, duration: 3.0)

        let loop = SKAction.sequence([moveLeft, moveRight])
        run(.repeatForever(loop))
    }

    // ====== Boss Damage ======
    func takeDamage(_ amount: Int) -> Bool {
        hp -= amount
        if hp <= 0 {
            die()
            return true
        }
        return false
    }

    // ====== Death ======
    private func die() {
        let fade = SKAction.fadeOut(withDuration: 0.4)
        let remove = SKAction.removeFromParent()
        run(.sequence([fade, remove]))
    }

    // ====== Attacks ======
    func update(dt: TimeInterval, playerPosition: CGPoint, scene: SKScene) {
        timeSinceLastAttack += dt

        if timeSinceLastAttack >= attackInterval {
            timeSinceLastAttack = 0
            fireProjectile(toward: playerPosition, scene: scene)
        }
    }

    private func fireProjectile(toward target: CGPoint, scene: SKScene) {
        let orb = SKSpriteNode(imageNamed: "druidorb")
        orb.setScale(2.2)
        orb.position = self.position
        orb.zPosition = 300

        let body = SKPhysicsBody(circleOfRadius: orb.size.width / 2)
        body.affectedByGravity = false
        body.isDynamic = true
        body.categoryBitMask = Cat.druidOrb
        body.collisionBitMask = 0
        body.contactTestBitMask = Cat.finger
        orb.physicsBody = body

        let dx = target.x - orb.position.x
        let dy = target.y - orb.position.y
        let length = max(1, hypot(dx, dy))
        let ux = dx / length
        let uy = dy / length

        body.velocity = CGVector(dx: ux * 300, dy: uy * 300)

        scene.addChild(orb)
    }
}
