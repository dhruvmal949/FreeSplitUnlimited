//
//  ConfettiCannon.swift
//  FreeSplitUnlimited
//

import SwiftUI

struct ConfettiCannon: View {
    @State private var pieces: [Piece] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    Capsule()
                        .fill(piece.color)
                        .frame(width: piece.width, height: piece.height)
                        .rotationEffect(.degrees(piece.spin))
                        .position(piece.fallen ? piece.end(in: geo.size) : piece.start(in: geo.size))
                        .opacity(piece.fallen ? 0 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            pieces = (0..<40).map(Piece.init)
            withAnimation(.easeIn(duration: 2.4)) {
                for index in pieces.indices {
                    pieces[index].fallen = true
                }
            }
        }
    }

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let width: CGFloat
        let height: CGFloat
        let drift: CGFloat
        let spin: Double
        let color: Color
        var fallen = false

        init(_ index: Int) {
            id = index
            x = CGFloat((index * 37) % 100) / 100
            width = CGFloat(5 + (index % 6))
            height = CGFloat(9 + (index % 8))
            drift = CGFloat((index % 9) - 4) * 8
            spin = Double(index * 17 % 360)
            let palette: [Color] = [
                AppTheme.teal,
                AppTheme.brightTeal,
                AppTheme.deepTeal,
                AppTheme.paleGold,
                AppTheme.seaFoam,
                Color.white,
                Color.orange.opacity(0.9)
            ]
            color = palette[index % palette.count]
        }

        func start(in size: CGSize) -> CGPoint {
            CGPoint(x: x * size.width, y: -24)
        }

        func end(in size: CGSize) -> CGPoint {
            CGPoint(x: x * size.width + drift, y: size.height + 40)
        }
    }
}
