import SwiftUI

struct EmptyStateView: View {
    @Environment(\.colorScheme) private var colorScheme
    var onAddTapped: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 88, height: 88)
                .background(
                    AppTheme.accent.opacity(0.18)
                )
                .background(AppTheme.surfaceSecondary(for: colorScheme), in: Circle())

            Text("No Schedules Yet")
                .font(.title2)
                .fontWeight(.heavy)

            Text("Tap the + button to create your first schedule and stay on top of your routine.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                onAddTapped()
            } label: {
                Label("Add Schedule", systemImage: "plus")
                    .font(.headline.weight(.bold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(LiquidGlassCapsuleButtonStyle())
            .padding(.top, 8)

            Spacer()
        }
    }
}

private struct PremiumCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
