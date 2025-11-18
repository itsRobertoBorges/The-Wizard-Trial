//
//  WitheringForestScene.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2025-11-13.
//


import SpriteKit

final class WitheringForestScene: SKScene {

    private let player = SKSpriteNode(imageNamed: "wizard")

    override func didMove(to view: SKView) {
        backgroundColor = .black
        
        // 1) Set up forest background
        let bg = SKSpriteNode(imageNamed: "witheringforestbg")
        bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
        bg.zPosition = -10
        bg.size = size
        addChild(bg)

        // 2) Set up player
        player.position = CGPoint(x: size.width / 2, y: size.height / 2)
        player.setScale(3.0)
        addChild(player)

        // 3) (Later) spawn enemies, waves, etc.
    }

    override func update(_ currentTime: TimeInterval) {
        // reuse your joystick logic
        // move player, handle projectiles, etc.
    }
}
