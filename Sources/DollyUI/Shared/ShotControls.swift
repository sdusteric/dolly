import SwiftUI

/// Shot mode renders views with ImageRenderer in a process that must never register as an app.
/// AppKit-backed controls (text fields, sliders, steppers, switches, segmented pickers) make it
/// register, so in shot mode each control draws a static look-alike instead.
public extension EnvironmentValues {
    @Entry var dollyShot = false
}

enum ShotControls {
    static func field(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.sheet.color))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.control.color, lineWidth: 1))
    }

    static func segmented(_ labels: [String], selected: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Text(label)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(i == selected ? Theme.ink.color : Theme.muted.color)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(i == selected ? Theme.sheet.color : .clear))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.active.color))
    }

    static func slider(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.control.color).frame(height: 4)
                Capsule().fill(Theme.ink.color).frame(width: geo.size.width * fraction, height: 4)
                Circle().fill(Theme.sheet.color).overlay(Circle().strokeBorder(Theme.control.color, lineWidth: 1))
                    .frame(width: 16, height: 16)
                    .offset(x: geo.size.width * fraction - 8)
            }
            .frame(height: 16)
        }
        .frame(height: 16)
    }

    static func stepper() -> some View {
        VStack(spacing: 0) {
            Image(systemName: "chevron.up").font(.system(size: 7, weight: .bold))
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(Theme.muted.color)
        .frame(width: 14, height: 20)
        .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.control.color, lineWidth: 1))
    }

    static func toggle(_ on: Bool) -> some View {
        Capsule().fill(on ? Theme.ink.color : Theme.control.color)
            .frame(width: 28, height: 16)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(Theme.sheet.color).frame(width: 12, height: 12).padding(2)
            }
    }
}
