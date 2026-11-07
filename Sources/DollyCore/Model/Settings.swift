import Foundation

/// `settings.json` (spec 8). Every field has a default, so older and newer files both load.
public struct Settings: Codable, Hashable, Sendable {
    public enum ClickSource: String, Codable, Sendable { case poll, monitor }

    /// The owner's spike switches (plan Task 21): off until S1 and S2 pass.
    public struct Advanced: Codable, Hashable, Sendable {
        public var clickSource: ClickSource = .poll
        public var pointerShapes = false
        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            clickSource = try c.decodeIfPresent(ClickSource.self, forKey: .clickSource) ?? .poll
            pointerShapes = try c.decodeIfPresent(Bool.self, forKey: .pointerShapes) ?? false
        }
    }

    public var hotkey: HotkeyCombo = .defaultRecord
    /// "Use for new takes" in the inspector (spec 6.4).
    public var defaultLook = Look()
    /// nil keeps exports in ~/Movies/Dolly (or DOLLY_HOME).
    public var exportsFolder: String?
    public var exportFPS = 60
    /// Writes the Shelf poster (status/dolly/poster.jpg); off by default (app-updates CONTRACT.md).
    public var showInShelf = false
    public var advanced = Advanced()
    /// The Record bar's Camera and Microphone switches and devices, remembered across launches.
    public var recordCamera = false
    public var recordMicrophone = false
    public var cameraID: String?
    public var microphoneID: String?
    /// The Record bar's System audio switch.
    public var recordSystemAudio = false
    /// The stage's "Drag inside the corners" hint stops showing after the first re-aim.
    public var aimHintSeen = false

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try c.decodeIfPresent(HotkeyCombo.self, forKey: .hotkey) ?? .defaultRecord
        defaultLook = try c.decodeIfPresent(Look.self, forKey: .defaultLook) ?? Look()
        exportsFolder = try c.decodeIfPresent(String.self, forKey: .exportsFolder)
        exportFPS = try c.decodeIfPresent(Int.self, forKey: .exportFPS) ?? 60
        showInShelf = try c.decodeIfPresent(Bool.self, forKey: .showInShelf) ?? false
        advanced = try c.decodeIfPresent(Advanced.self, forKey: .advanced) ?? Advanced()
        recordCamera = try c.decodeIfPresent(Bool.self, forKey: .recordCamera) ?? false
        recordMicrophone = try c.decodeIfPresent(Bool.self, forKey: .recordMicrophone) ?? false
        cameraID = try c.decodeIfPresent(String.self, forKey: .cameraID)
        microphoneID = try c.decodeIfPresent(String.self, forKey: .microphoneID)
        recordSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .recordSystemAudio) ?? false
        aimHintSeen = try c.decodeIfPresent(Bool.self, forKey: .aimHintSeen) ?? false
    }
}
