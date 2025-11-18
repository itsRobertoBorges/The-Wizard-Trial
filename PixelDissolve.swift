//
//  PixelDissolve.swift
//  The Wizard's Trial
//
//  Created by Roberto on 2025-11-11.
//


import SwiftUI

struct PixelDissolve: AnimatableModifier {
    var progress: CGFloat        // 0 → 1
    let columns: Int
    let rows: Int

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { geo in
                    Canvas { ctx, size in
                        let cw = size.width / CGFloat(columns)
                        let ch = size.height / CGFloat(rows)
                        let total = columns * rows

                        for r in 0..<rows {
                            for c in 0..<columns {
                                let idx = r * columns + c
                                // deterministic pseudo-random reveal order
                                let t = CGFloat((idx * 73) % total) / CGFloat(total)
                                if progress >= t {
                                    let rect = CGRect(x: CGFloat(c)*cw,
                                                      y: CGFloat(r)*ch,
                                                      width: cw, height: ch)
                                    ctx.fill(Path(rect), with: .color(.white))
                                }
                            }
                        }
                    }
                }
            )
    }
}

extension AnyTransition {
    static func pixelDissolve(columns: Int = 16, rows: Int = 28) -> AnyTransition {
        .modifier(
            active:   PixelDissolve(progress: 0, columns: columns, rows: rows),
            identity: PixelDissolve(progress: 1, columns: columns, rows: rows)
        )
    }
}
