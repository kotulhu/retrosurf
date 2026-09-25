import SwiftUI

struct BrandLogo: View {
    let skin: AppSkin
    let isLoading: Bool

    var body: some View {
        switch skin {
        case .cheesecake:
            CheesecakeLogo(isLoading: isLoading)
        case .internetExplorer:
            IELogo(isLoading: isLoading)
        }
    }
}

private struct CheesecakeLogo: View {
    var isLoading: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.53, green: 0.40, blue: 0.76),
                            Color(red: 0.24, green: 0.14, blue: 0.46)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                )
            Text("C")
                .font(.custom("Times New Roman", size: 20))
                .italic()
                .bold()
                .foregroundColor(.white)
        }
        .frame(width: 32, height: 32)
        .overlay(
            OrbitRing(
                color: Color(red: 0.45, green: 0.33, blue: 0.72),
                isLoading: isLoading
            )
        )
    }
}

private struct IELogo: View {
    var isLoading: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.24, green: 0.49, blue: 0.79),
                            Color(red: 0.06, green: 0.24, blue: 0.50)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                )
            Text("e")
                .font(.custom("Times New Roman", size: 20))
                .italic()
                .bold()
                .foregroundColor(.white)
        }
        .frame(width: 32, height: 32)
        .overlay(
            OrbitRing(
                color: Color(red: 1.00, green: 0.85, blue: 0.10),
                isLoading: isLoading
            )
        )
    }
}

private struct OrbitRing: View {
    let color: Color
    var isLoading: Bool

    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.75), lineWidth: 2)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .offset(y: -19)
        }
        .frame(width: 38, height: 38)
        .rotationEffect(.degrees(angle))
        .opacity(isLoading ? 1 : 0.35)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
    }
}