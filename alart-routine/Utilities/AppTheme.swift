import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.31, green: 0.62, blue: 0.97)
    static let accentSoft = Color(red: 0.39, green: 0.72, blue: 0.99)
    static let success = Color(red: 0.24, green: 0.79, blue: 0.47)
    static let warning = Color(red: 0.96, green: 0.66, blue: 0.33)
    static let danger = Color(red: 0.96, green: 0.40, blue: 0.42)

    static func priorityColor(_ priority: SchedulePriority) -> Color {
        switch priority {
        case .high:
            return Color(red: 0.96, green: 0.48, blue: 0.42)
        case .medium:
            return Color(red: 0.95, green: 0.73, blue: 0.42)
        case .low:
            return Color(red: 0.48, green: 0.74, blue: 0.96)
        case .none:
            return Color.secondary
        }
    }

    static func backgroundBaseColors(for scheme: ColorScheme) -> [Color] {
        switch scheme {
        case .dark:
            return [
                Color(red: 0.018, green: 0.020, blue: 0.030),
                Color(red: 0.040, green: 0.052, blue: 0.084),
                Color(red: 0.016, green: 0.020, blue: 0.034),
                Color(red: 0.012, green: 0.015, blue: 0.026)
            ]
        default:
            return [
                Color(red: 0.985, green: 0.991, blue: 1.000),
                Color(red: 0.938, green: 0.958, blue: 0.992),
                Color(red: 0.963, green: 0.976, blue: 0.996)
            ]
        }
    }

    static func surfacePrimary(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(red: 0.118, green: 0.120, blue: 0.132).opacity(0.82)
        default:
            return Color(red: 0.985, green: 0.991, blue: 1.000)
        }
    }

    static func surfaceSecondary(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(red: 0.094, green: 0.098, blue: 0.112).opacity(0.80)
        default:
            return Color(red: 0.969, green: 0.979, blue: 0.996)
        }
    }

    static func surfaceTertiary(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(red: 0.132, green: 0.136, blue: 0.151).opacity(0.76)
        default:
            return Color(red: 0.944, green: 0.959, blue: 0.986)
        }
    }

    static func borderStrong(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.20)
        default:
            return Color(red: 0.73, green: 0.80, blue: 0.93).opacity(0.72)
        }
    }

    static func borderSoft(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.13)
        default:
            return Color(red: 0.58, green: 0.66, blue: 0.82).opacity(0.28)
        }
    }

    static func cardShadow(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.black.opacity(0.42)
        default:
            return Color(red: 0.14, green: 0.21, blue: 0.33).opacity(0.16)
        }
    }

    static func mutedTimeline(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(red: 0.56, green: 0.60, blue: 0.69)
        default:
            return Color(red: 0.61, green: 0.66, blue: 0.75)
        }
    }

    static func chipFill(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color.white.opacity(0.11)
        default:
            return Color(red: 0.88, green: 0.92, blue: 0.98)
        }
    }

    static func panelGradient(for scheme: ColorScheme) -> LinearGradient {
        switch scheme {
        case .dark:
            return LinearGradient(
                colors: [
                    Color(red: 0.136, green: 0.140, blue: 0.154).opacity(0.88),
                    Color(red: 0.082, green: 0.086, blue: 0.098).opacity(0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [
                    Color(red: 0.995, green: 0.998, blue: 1.000),
                    Color(red: 0.955, green: 0.970, blue: 0.995)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func stackCardGradient(
        for scheme: ColorScheme,
        priority: SchedulePriority,
        completed: Bool
    ) -> LinearGradient {
        let base: [Color]
        switch scheme {
        case .dark:
            base = [
                Color(red: 0.172, green: 0.176, blue: 0.192).opacity(completed ? 0.62 : 0.90),
                Color(red: 0.116, green: 0.120, blue: 0.136).opacity(completed ? 0.58 : 0.86)
            ]
        default:
            base = [
                Color(red: 0.995, green: 0.998, blue: 1.000),
                Color(red: 0.956, green: 0.969, blue: 0.992)
            ]
        }

        let accent: Color
        if priority == .none {
            accent = scheme == .dark
                ? Color.white.opacity(completed ? 0.04 : 0.10)
                : accentSoft.opacity(completed ? 0.06 : 0.16)
        } else {
            accent = priorityColor(priority).opacity(scheme == .dark ? (completed ? 0.10 : 0.24) : (completed ? 0.10 : 0.20))
        }

        return LinearGradient(
            colors: [accent, base[0], base[1]],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func stackCardBorder(
        for scheme: ColorScheme,
        priority: SchedulePriority,
        completed: Bool
    ) -> Color {
        if completed {
            return success.opacity(scheme == .dark ? 0.65 : 0.58)
        }
        switch priority {
        case .none:
            return scheme == .dark
                ? Color.white.opacity(0.16)
                : Color(red: 0.67, green: 0.74, blue: 0.88).opacity(0.46)
        default:
            return priorityColor(priority).opacity(scheme == .dark ? 0.48 : 0.34)
        }
    }
}

struct PremiumAppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: AppTheme.backgroundBaseColors(for: colorScheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.34, green: 0.52, blue: 0.92).opacity(colorScheme == .dark ? 0.30 : 0.24),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 16,
                endRadius: 560
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    Color(red: 0.52, green: 0.38, blue: 0.78).opacity(colorScheme == .dark ? 0.22 : 0.14),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 520
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    Color(red: 0.28, green: 0.66, blue: 0.60).opacity(colorScheme == .dark ? 0.22 : 0.15),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 22,
                endRadius: 540
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    Color(red: 0.28, green: 0.44, blue: 0.82).opacity(colorScheme == .dark ? 0.18 : 0.11),
                    Color(red: 0.72, green: 0.48, blue: 0.28).opacity(colorScheme == .dark ? 0.12 : 0.06),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 560
            )
            .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}
