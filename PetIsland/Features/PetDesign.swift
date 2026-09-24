import SwiftUI
import UIKit

/// Quiet Island: neutral surfaces let the original pixel characters carry the color.
/// Dynamic UIColors also resolve correctly in sheets and native navigation controls.
enum PetDesign {
    static let background = adaptive(0xF7F8FA, 0x1C1D20)
    static let surface = adaptive(0xFFFFFF, 0x292C30)
    static let ink = adaptive(0x292F35, 0xEDF0F3)
    static let secondary = adaptive(0x626C76, 0xADB5BF)
    static let accent = adaptive(0x37414B, 0xDAE1E8)
    static let onAccent = adaptive(0xFFFFFF, 0x252D35)
    static let soft = adaptive(0xECEFF3, 0x353B42)
    static let separator = adaptive(0xDFE4E9, 0x414850)
    static let sky = adaptive(0xEDF1F5, 0x2D3034)
    static let horizon = adaptive(0xE3E9EF, 0x373C42)
    static let hill = adaptive(0xCDD7E0, 0x50575F)
    static let light = adaptive(0xD3DCE5, 0x9199A1)

    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static func title(_ style: Font.TextStyle = .title) -> Font {
        .system(style, design: .rounded).weight(.semibold)
    }
}

struct PetScreenHeading: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(PetDesign.title())
            .foregroundStyle(PetDesign.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PetPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(PetButtonLabelStyle())
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(PetDesign.onAccent)
            .background(PetDesign.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.8 : 1)
    }
}

struct PetQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(PetButtonLabelStyle())
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 14)
            .foregroundStyle(PetDesign.ink)
            .background(PetDesign.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}

private struct PetButtonLabelStyle: LabelStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            configuration.title
        } else {
            HStack(spacing: 8) {
                configuration.icon
                configuration.title
            }
        }
    }
}

extension View {
    func petSurface(radius: CGFloat = 24) -> some View {
        background(PetDesign.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    func petPage() -> some View {
        background(PetDesign.background)
            .foregroundStyle(PetDesign.ink)
            .tint(PetDesign.accent)
            .toolbarBackground(PetDesign.background, for: .navigationBar)
    }
}
