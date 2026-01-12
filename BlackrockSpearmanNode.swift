import SpriteKit

final class BlackrockSpearmanNode: SKSpriteNode {

    // MARK: - Config
    private let moveSpeed: CGFloat = 140   // points per second

    // MARK: - Init
    init(startX: CGFloat, sceneHeight: CGFloat) {
        let texture = SKTexture(imageNamed: "orcspear")
        super.init(texture: texture, color: .clear, size: texture.size())

        name = "BlackrockSpearman"

        // Spawn slightly above screen
        position = CGPoint(
            x: startX,
            y: sceneHeight + size.height
        )

        zPosition = 10
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        startMovingDown(sceneHeight: sceneHeight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Movement
    private func startMovingDown(sceneHeight: CGFloat) {
        let distance = sceneHeight + size.height * 2
        let duration = TimeInterval(distance / moveSpeed)

        let moveDown = SKAction.moveBy(
            x: 0,
            y: -distance,
            duration: duration
        )

        let cleanup = SKAction.removeFromParent()

        run(SKAction.sequence([moveDown, cleanup]))
    }
}
