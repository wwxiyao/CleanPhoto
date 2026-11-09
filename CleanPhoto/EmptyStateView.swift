import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "photo.on.rectangle.angled"
    var accent: Color = AppPalette.primary
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppPalette.backgroundTop, AppPalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 72, height: 72)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text(title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                }

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            )
            .padding()
        }
    }
}

enum AppPalette {
    static let primary = Color(red: 0.10, green: 0.47, blue: 0.95)
    static let danger = Color(red: 0.88, green: 0.22, blue: 0.27)
    static let success = Color(red: 0.12, green: 0.64, blue: 0.41)
    static let backgroundTop = Color(red: 0.95, green: 0.98, blue: 1.00)
    static let backgroundBottom = Color(red: 0.92, green: 0.95, blue: 0.99)
}

#Preview {
    EmptyStateView(
        title: "No Photos",
        message: "Allow access to your photo library to get started.",
        actionTitle: "Allow Access",
        action: {}
    )
}
