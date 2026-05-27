import SwiftUI

struct BoothifyLogoView: View {
    var size: CGFloat = 80

    var body: some View {
        Image("BoothifyLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: BoothifyTheme.violet.opacity(0.5), radius: 22, y: 8)
            .accessibilityLabel("Boothify")
    }
}

#Preview {
    ZStack {
        BoothifyTheme.bg.ignoresSafeArea()
        BoothifyLogoView(size: 120)
    }
}
