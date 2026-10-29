import DollyCore
import SwiftUI

/// A camera or microphone for the Record bar's device menus.
nonisolated public struct DeviceOption: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The devices the bar offers and what its switches do (the app checks permission first).
public struct RecordBarDevices {
    public var cameras: [DeviceOption] = []
    public var microphones: [DeviceOption] = []
    public var toggleCamera: () -> Void = {}
    public var toggleMicrophone: () -> Void = {}
    public init() {}
}

/// The Record bar (spec 4.1, studio spec Camera): pick Window, Area or Display, the Camera and
/// Microphone switches, then Record. A floating panel near the top of the screen; Esc cancels.
/// Excluded from every recording.
public struct RecordBar: View {
    @Binding var model: RecordBarModel
    let windows: [PickableWindow]
    let shortcut: String
    let devices: RecordBarDevices
    let record: () -> Void
    let cancel: () -> Void
    @Environment(\.dollyShot) private var shot

    public init(model: Binding<RecordBarModel>, windows: [PickableWindow], shortcut: String, devices: RecordBarDevices = RecordBarDevices(),
                record: @escaping () -> Void, cancel: @escaping () -> Void) {
        _model = model
        self.windows = windows
        self.shortcut = shortcut
        self.devices = devices
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

            deviceSwitch("Camera", symbol: "video", on: model.camera, options: devices.cameras, selected: model.cameraID,
                         toggle: devices.toggleCamera) { model.cameraID = $0 }
            deviceSwitch("Microphone", symbol: "mic", on: model.microphone, options: devices.microphones, selected: model.microphoneID,
                         toggle: devices.toggleMicrophone) { model.microphoneID = $0 }

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

    /// A switch that reads as one: the device's name in ink with a filled symbol when on, muted with
    /// a slashed one when off, and a menu of devices beside it.
    private func deviceSwitch(_ name: String, symbol: String, on: Bool, options: [DeviceOption], selected: String?,
                              toggle: @escaping () -> Void, choose: @escaping (String) -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 5) {
                    Image(systemName: on ? "\(symbol).fill" : "\(symbol).slash").frame(width: 16)
                    Text(name)
                }
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(on ? Theme.ink.color : Theme.muted.color)
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityValue(on ? "On" : "Off")
            deviceMenu(name, options: options, selected: selected, choose: choose)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.sheet.color : Theme.active.color))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? Theme.control.color : .clear, lineWidth: 1))
    }

    @ViewBuilder
    private func deviceMenu(_ name: String, options: [DeviceOption], selected: String?, choose: @escaping (String) -> Void) -> some View {
        let chevron = Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted.color)
        if shot || options.isEmpty {
            chevron.frame(width: 18, height: 26).opacity(options.isEmpty && !shot ? 0 : 1)
        } else {
            Menu {
                Picker(name, selection: Binding(get: { selected ?? options[0].id }, set: choose)) {
                    ForEach(options) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: { chevron }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 18, height: 26)
                .accessibilityLabel("\(name) device")
        }
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
    let copy: PermissionWindowModel.Copy
    let denied: Bool
    let allow: () -> Void
    let openSettings: () -> Void

    public init(copy: PermissionWindowModel.Copy = PermissionWindowModel.screen, denied: Bool, allow: @escaping () -> Void,
                openSettings: @escaping () -> Void) {
        self.copy = copy
        self.denied = denied
        self.allow = allow
        self.openSettings = openSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(copy.title).font(Theme.Font.display(18)).accessibilityAddTraits(.isHeader)
            Text(copy.message).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            if denied {
                Text(copy.deniedHint).font(Theme.Font.body).foregroundStyle(Theme.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(PermissionWindowModel.openSettings, action: openSettings).buttonStyle(DollyButtonStyle())
                Button(copy.allow, action: allow).buttonStyle(DollyButtonStyle(kind: .primary))
            }
        }
        .foregroundStyle(Theme.ink.color)
        .padding(24)
        .frame(width: 440)
        .background(Theme.sheet.color)
    }
}
