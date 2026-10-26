import DollyCore
import Observation
import SwiftUI

/// The Advanced section's words (plan Task 21): the owner's spike switches and the live readout
/// that shows whether a click arrived.
nonisolated public enum AdvancedSettingsModel {
    public static func showsAdvanced(optionHeld: Bool) -> Bool { optionHeld }

    public static func readoutText(lastClickAgo: Double?, point: (Int, Int)?, source: DollyCore.Settings.ClickSource) -> String {
        guard let ago = lastClickAgo, let point else { return "No click yet. Click anywhere to test." }
        let from = source == .poll ? "polling" : "the event monitor"
        return "Last click: \(String(format: "%.1f", ago)) s ago at (\(point.0), \(point.1)), from \(from)"
    }
}

/// What the Settings window shows. The app owns saving and the click probe; shot mode fills it in.
@Observable
public final class SettingsScreenModel {
    public var settings: DollyCore.Settings
    public var showsAdvanced: Bool
    public var takesFolder: String
    /// The last click the probe saw: global point and when.
    public var lastClick: (point: CGPoint, at: Date)?
    @ObservationIgnored public var onChange: (DollyCore.Settings) -> Void = { _ in }
    @ObservationIgnored public var revealTakes: () -> Void = {}

    public init(settings: DollyCore.Settings, showsAdvanced: Bool, takesFolder: String) {
        self.settings = settings
        self.showsAdvanced = showsAdvanced
        self.takesFolder = takesFolder
    }

    func update(_ change: (inout DollyCore.Settings) -> Void) {
        change(&settings)
        onChange(settings)
    }

    func readout(now: Date) -> String {
        AdvancedSettingsModel.readoutText(
            lastClickAgo: lastClick.map { max(now.timeIntervalSince($0.at), 0) },
            point: lastClick.map { (Int($0.point.x.rounded()), Int($0.point.y.rounded())) },
            source: settings.advanced.clickSource
        )
    }
}

/// Dolly > Settings (⌘,). Advanced appears only when the window opens with Option held.
public struct SettingsView: View {
    @Bindable var model: SettingsScreenModel
    let now: Date?
    @Environment(\.dollyShot) private var shot

    /// `now` freezes the readout's clock (shot mode); nil ticks live.
    public init(model: SettingsScreenModel, now: Date? = nil) {
        self.model = model
        self.now = now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            general
            if model.showsAdvanced {
                Rectangle().fill(Theme.border.color).frame(height: 1).padding(.vertical, 20)
                advanced
            }
        }
        .padding(24)
        .frame(width: 480, alignment: .topLeading)
        .font(Theme.Font.body)
        .foregroundStyle(Theme.ink.color)
        .background(Theme.sheet.color)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Record") {
                Text(model.settings.hotkey.displayString)
                    .font(Theme.Font.bodyMedium)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.raised.color))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border.color, lineWidth: 1))
            }
            row("Show in Shelf", note: "Shelf shows the poster of your newest export.") {
                toggle(model.settings.showInShelf) { on in model.update { $0.showInShelf = on } }
            }
            row("Takes") {
                HStack(spacing: 12) {
                    Text(model.takesFolder).foregroundStyle(Theme.muted.color).lineLimit(1).truncationMode(.middle)
                    Button("Show in Finder", action: model.revealTakes).buttonStyle(DollyButtonStyle())
                }
            }
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced").font(Theme.Font.display(15)).accessibilityAddTraits(.isHeader)
            row("Clicks from") {
                if shot {
                    ShotControls.segmented(["Polling", "Event monitor"], selected: model.settings.advanced.clickSource == .poll ? 0 : 1)
                        .frame(width: 220)
                } else {
                    Picker("Clicks from", selection: Binding(
                        get: { model.settings.advanced.clickSource },
                        set: { source in model.update { $0.advanced.clickSource = source } }
                    )) {
                        Text("Polling").tag(DollyCore.Settings.ClickSource.poll)
                        Text("Event monitor").tag(DollyCore.Settings.ClickSource.monitor)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
            row("Record pointer shapes") {
                toggle(model.settings.advanced.pointerShapes) { on in model.update { $0.advanced.pointerShapes = on } }
            }
            Group {
                if let now {
                    Text(model.readout(now: now))
                } else {
                    SwiftUI.TimelineView(.periodic(from: .now, by: 0.1)) { context in Text(model.readout(now: context.date)) }
                }
            }
            .font(Theme.Font.body)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Size.controlRadius).fill(Theme.raised.color))
            .accessibilityLabel("Click test")
            Text("Changes apply to the next recording.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.muted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Label left, control right and centered on the label's line, the note under both (as in the inspector).
    private func row(_ label: String, note: String? = nil, @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 16) {
                Text(label).font(Theme.Font.bodyMedium)
                Spacer(minLength: 16)
                control()
            }
            if let note {
                Text(note).font(Theme.Font.meta).foregroundStyle(Theme.muted.color).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func toggle(_ on: Bool, set: @escaping (Bool) -> Void) -> some View {
        if shot {
            ShotControls.toggle(on)
        } else {
            Toggle("", isOn: Binding(get: { on }, set: set))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.ink.color)
                .labelsHidden()
        }
    }
}
