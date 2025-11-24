// Right analog + quick slots
ZStack {
    AnalogStickView(
        size: geo.size.width * 0.24,
        onChange: { vector in
            let mag = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
            if mana <= 0 {
                isShooting = false
                scene.setAttackInput(.zero)
            } else {
                isShooting = (mag > 0.15)
                scene.setAttackInput(vector)
            }
        },
        onEnd: {
            isShooting = false
            scene.setAttackInput(.zero)
        }
    )

    // SLOT 1 — ABOVE
    QuickSlotButton(
        item: inventory.quickSlots[0],
        action: { handleQuickSlotUse(index: 0) },
        cooldownRemaining: cooldownRemaining(for: inventory.quickSlots[0])
    )
    .offset(x: 0, y: -geo.size.width * 0.20)

    // SLOT 2 — RIGHT
    QuickSlotButton(
        item: inventory.quickSlots[1],
        action: { handleQuickSlotUse(index: 1) },
        cooldownRemaining: cooldownRemaining(for: inventory.quickSlots[1])
    )
    .offset(x: geo.size.width * 0.20, y: -geo.size.width * 0.02)

    // SLOT 3 — BELOW
    QuickSlotButton(
        item: inventory.quickSlots[2],
        action: { handleQuickSlotUse(index: 2) },
        cooldownRemaining: cooldownRemaining(for: inventory.quickSlots[2])
    )
    .offset(x: 0, y: geo.size.width * 0.20)
}
.padding(.trailing, 60)     // << 🔥 KEY FIX: pushes everything LEFT
.padding(.bottom, 24)
