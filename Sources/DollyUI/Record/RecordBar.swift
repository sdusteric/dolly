import DollyCore
import SwiftUI

/// The Record bar (spec 4.1): pick Window, Area or Display, then Record. A floating panel near the
/// top of the screen; Esc cancels. Excluded from every recording.
public struct RecordBar: View {
    @Binding var model: RecordBarModel
    let windows: [PickableWindow]
    let shortcut: String
    let record: () -> Void
    let cancel: () -> Void
    @Environment(\.dollyShot) private var shot

    public init(model: Binding<RecordBarModel>, windows: [PickableWindow], shortcut: String,
                record: @escaping () -> Void, cancel: @escaping () -> Void) {
        _model = model
        self.windows = windows
        self.shortcut = shortcut
        self.record = record
        self.cancel = cancel
    }

    public var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(RecordBarModel.targets, id: \.self) { target in
                    Button { model.target = target } label: {
                        Text(RecordBarModel.label(target))
                            .font(Theme.Font.bodyMedium)
                            .foregroundStyle(model.target == target ? Theme.ink.color : Theme.muted.color)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 5).fill(model.target == target ? Theme.sheet.color : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.target == target ? .isSelected : [])
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.active.color))

            if model.target == .window { windowPicker.frame(width: 260) }

            Button(action: record) {
                HStack(spacing: 6) { RecordDot(); Text("Record"); ShortcutHint(text: shortcut) }
            }
            .buttonStyle(DollyButtonStyle(kind: .primary))
            .disabled(!model.canRecord)
            .opacity(model.canRecord ? 1 : 0.4)
            .keyboardShortcut(.defaultAction)

            Button("Cancel", action: cancel)
                .buttonStyle(DollyButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.sheet.color))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border.color, lineWidth: 1))
        // The bar floats over other apps, the one place a shadow belongs. Grouped first, so only
        // the bar casts it, not every button inside.
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    @ViewBuilder private var windowPicker: some View {
        let chosen = windows.first { $0.id == model.windowID }
        if shot {
            ShotControls.field(chosen?.label ?? "Choose a window")
        } else {
            Picker("Window", selection: $model.windowID) {
                Text("Choose a window").tag(UInt32?.none)
                ForEach(windows) { window in Text(window.label).tag(UInt32?.some(window.id)) }
            }
            .labelsHidden()
        }
    }
}

/// The 3, 2, 1 before recording (spec 10.6: each number crossfades in 200 ms; Reduce Motion is instant).
public struct CountdownView: View {
    let number: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(number: Int) { self.number = number }

    public var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.55)).frame(width: 88, height: 88)
            Text("\(number)")
                .font(.system(size: 44, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .id(number)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.countdown), value: number)
        .accessibilityLabel("Recording starts in \(number)")
    }
}

/// The menu bar timer while recording: a record-red capsule with a stop square and the time.
public struct StatusTimerView: View {
    let elapsed: Double

    public init(elapsed: Double) { self.elapsed = elapsed }

    public var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 8, height: 8)
            Text(RecordBarModel.timerText(elapsed: elapsed))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(Theme.record.color))
        .accessibilityLabel("Recording, \(RecordBarModel.timerText(elapsed: elapsed)). Click to stop.")
    }
}

/// First Record without Screen Recording (Snap's first-run pattern): why, one button that asks
/// macOS, and a hint with the settings link if it stays denied.
public struct PermissionWindowView: View {
    let denied: Bool
    let allow: () -> Void
    let openSettings: () -> Void

    public init(denied: Bool, allow: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.denied = denied
        self.allow = allow
        self.openSettings = openSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(PermissionWindowModel.title).font(Theme.Font.display(18)).accessibilityAddTraits(.isHeader)
            Text(PermissionWindowModel.message).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            if denied {
                Text(PermissionWindowModel.deniedHint).font(Theme.Font.body).foregroundStyle(Theme.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(PermissionWindowModel.openSettings, action: openSettings).buttonStyle(DollyButtonStyle())
                Button(PermissionWindowModel.allow, action: allow).buttonStyle(DollyButtonStyle(kind: .primary))
            }
        }
        .foregroundStyle(Theme.ink.color)
        .padding(24)
        .frame(width: 440)
        .background(Theme.sheet.color)
    }
}
