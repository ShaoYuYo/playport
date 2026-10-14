// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Glass belongs to navigation and controls; artwork and game content stay flat.
/// Native GlassEffectContainer callers share sampling between nearby controls.
private struct PlayportGlass: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glass: Glass {
        let base = Glass.regular.interactive(interactive && !reduceMotion)
        return tint.map { base.tint($0) } ?? base
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(PP.surface, in: shape)
                .overlay { shape.strokeBorder(tint ?? PP.line, lineWidth: 1) }
        } else {
            content.glassEffect(glass, in: shape)
        }
    }
}

/// Native button styles supply the system's pressed feedback and Liquid Glass
/// motion. Opaque bordered styles retain contrast when transparency is reduced.
private struct PlayportGlassButton: ViewModifier {
    var prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        } else {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        }
    }
}

extension View {
    func ppGlass(cornerRadius: CGFloat = 14, tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(PlayportGlass(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    func ppGlassButton(prominent: Bool = false) -> some View {
        modifier(PlayportGlassButton(prominent: prominent))
    }
}
