import SwiftUI

struct IntroCaptionBar: View {
    let text: String   // already-typed text coming from IntroView

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // shop-style bubble
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.65))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 2)

                // just render the text you pass in
                Text(text)
                    .font(.custom("PressStart2P-Regular", size: bestFontSize(forWidth: geo.size.width)))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(height: 140)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func bestFontSize(forWidth w: CGFloat) -> CGFloat {
        switch w {
        case ..<340: return 10
        case ..<380: return 11
        case ..<420: return 12
        default:     return 13
        }
    }
}
