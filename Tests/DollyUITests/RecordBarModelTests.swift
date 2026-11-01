import CoreGraphics
import Foundation
import Testing
@testable import DollyCore
@testable import DollyUI

@Suite struct RecordBarModelTests {
    @Test func hotkeyOpensBarWhenIdleAndStopsWhenRecording() {
        #expect(RecordBarModel.hotkey(in: .idle) == .openBar)
        #expect(RecordBarModel.hotkey(in: .failed("x")) == .openBar)
        #expect(RecordBarModel.hotkey(in: .recording(since: 1)) == .stop)
        #expect(RecordBarModel.hotkey(in: .countdown(2)) == .cancelCountdown)
        #expect(RecordBarModel.hotkey(in: .finishing) == .ignore)
    }

    @Test func timerTextAndTooltip() {
        #expect(RecordBarModel.timerText(elapsed: 42.4) == "0:42")
        #expect(RecordBarModel.tooltip(elapsed: 42, shortcut: "⌃⌥⌘R") == "Stop recording (⌃⌥⌘R)")
        #expect(RecordBarModel.tooltip(elapsed: 301, shortcut: "⌃⌥⌘R").hasSuffix("Longer than Threads allows"))
    }

    @Test func barOffersThreeTargetsWindowFirst() {
        #expect(RecordBarModel.targets == [.window, .area, .display])
        #expect(RecordBarModel().target == .window)
        #expect(RecordBarModel.label(.display) == "Display")
    }

    @Test func recordNeedsAWindowWhenTargetIsWindow() {
        var m = RecordBarModel()
        #expect(!m.canRecord)
        m.windowID = 42
        #expect(m.canRecord)
        m.target = .display
        m.windowID = nil
        #expect(m.canRecord)
    }

    private func window(_ id: UInt32, _ app: String, pid: Int32) -> PickableWindow {
        PickableWindow(id: id, app: app, title: "", frame: .zero, displayID: 1, pid: pid)
    }

    @Test func windowsListFrontToBack() {
        let windows = [window(1, "Notes", pid: 10), window(2, "Safari", pid: 20), window(3, "Xcode", pid: 30)]
        let ordered = PickableWindow.frontToBack(windows, order: [99, 3, 1, 2])
        #expect(ordered.map(\.id) == [3, 1, 2])
        // A window missing from the order goes last instead of disappearing.
        #expect(PickableWindow.frontToBack(windows, order: [2]).map(\.id) == [2, 1, 3])
    }

    @Test func barPicksTheFrontmostAppsTopWindow() {
        var m = RecordBarModel()
        m.prepare(windows: [window(5, "Xcode", pid: 30), window(6, "Safari", pid: 20), window(7, "Safari", pid: 20)], frontmostPID: 20)
        #expect(m.windowID == 6)
    }

    @Test func barFallsBackToTheTopWindowWhenDollyIsInFront() {
        var m = RecordBarModel()
        m.windowID = 99
        m.prepare(windows: [window(5, "Xcode", pid: 30), window(6, "Safari", pid: 20)], frontmostPID: 1)
        #expect(m.windowID == 5)
        m.prepare(windows: [], frontmostPID: 20)
        #expect(m.windowID == nil)
    }

    @Test func switchesStartOff() {
        let m = RecordBarModel()
        #expect(!m.camera && !m.microphone && m.cameraID == nil && m.microphoneID == nil)
    }

    @Test func turningCameraOnAsksOnce() {
        var m = RecordBarModel()
        #expect(m.permissionStep(camera: .notAsked, microphone: .notAsked) == nil)   // both off
        m.camera = true
        #expect(m.permissionStep(camera: .notAsked, microphone: .denied) == .askCamera)
        #expect(m.permissionStep(camera: .allowed, microphone: .denied) == nil)
        #expect(m.permissionStep(camera: .denied, microphone: .allowed) == .cameraDenied)
        m.microphone = true
        #expect(m.permissionStep(camera: .allowed, microphone: .notAsked) == .askMicrophone)
        #expect(m.permissionStep(camera: .allowed, microphone: .denied) == .microphoneDenied)
    }

    @Test func planCarriesDeviceIDs() throws {
        var plan = try RecordingPlan.make(target: .display, displayID: 1, windowID: nil,
                                          globalRect: CGRect(x: 0, y: 0, width: 640, height: 400), scale: 1)
        var m = RecordBarModel()
        m.camera = true
        m.cameraID = "cam-1"
        m.microphoneID = "mic-1"
        m.apply(to: &plan)
        #expect(plan.cameraID == "cam-1" && plan.microphoneID == nil)
        m.camera = false
        m.apply(to: &plan)
        #expect(plan.cameraID == nil)
    }

    @Test func barRemembersTheSwitches() throws {
        var settings = DollyCore.Settings()
        #expect(!settings.recordCamera && !settings.recordMicrophone)
        var m = RecordBarModel()
        m.camera = true
        m.microphone = true
        m.cameraID = "cam-1"
        m.store(in: &settings)
        let back = try JSONDecoder().decode(DollyCore.Settings.self, from: JSONEncoder().encode(settings))
        var n = RecordBarModel()
        n.load(from: back)
        #expect(n.camera && n.microphone && n.cameraID == "cam-1" && n.microphoneID == nil)
        let old = try JSONDecoder().decode(DollyCore.Settings.self, from: Data("{}".utf8))
        #expect(!old.recordCamera)
    }

    @Test func aimHintIsRememberedOnceSeen() throws {
        #expect(try !JSONDecoder().decode(DollyCore.Settings.self, from: Data("{}".utf8)).aimHintSeen)
        var settings = DollyCore.Settings()
        settings.aimHintSeen = true
        #expect(try JSONDecoder().decode(DollyCore.Settings.self, from: JSONEncoder().encode(settings)).aimHintSeen)
    }

    @Test func devicePermissionCopy() {
        #expect(PermissionWindowModel.camera.message
            == "Dolly needs Camera to record your camera. It never opens the camera unless the Camera switch is on.")
        #expect(PermissionWindowModel.microphone.message
            == "Dolly needs Microphone to record your voice. It never opens the microphone unless the Microphone switch is on.")
    }

    @Test func permissionCopy() {
        #expect(PermissionWindowModel.message == "Dolly needs Screen Recording to record your screen. It never records until you press Record.")
    }
}

@Suite struct TakeCardModelTests {
    @Test func metaCountsTheZooms() {
        #expect(TakeCardModel(name: "Demo", duration: 42.4, zooms: 3, size: CGSize(width: 1600, height: 900)).meta == "3 zooms")
        #expect(TakeCardModel(name: "Demo", duration: 5, zooms: 1, size: .zero).meta == "1 zoom")
        #expect(TakeCardModel(name: "Demo", duration: 5, zooms: 0, size: .zero).meta == "No zooms")
    }

    @Test func posterKeepsTheTakeShapeWithinLimits() {
        #expect(TakeCardModel(name: "", duration: 1, zooms: 0, size: CGSize(width: 1600, height: 900)).posterSize == CGSize(width: 240, height: 135))
        // A tall window stops at a square; a very wide strip stops at 96 pt.
        #expect(TakeCardModel(name: "", duration: 1, zooms: 0, size: CGSize(width: 600, height: 1200)).posterSize.height == 240)
        #expect(TakeCardModel(name: "", duration: 1, zooms: 0, size: CGSize(width: 3000, height: 200)).posterSize.height == 96)
    }

    @Test func cardSitsInTheBottomRightCorner() {
        let origin = TakeCardModel.origin(cardSize: CGSize(width: 260, height: 300), visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 835))
        #expect(origin == CGPoint(x: 1440 - 16 - 260, y: 56))
    }
}

@Suite struct EditorStepAsideTests {
    @Test func visibleEditorHidesAndComesBackOnCancel() {
        var aside = EditorStepAside()
        let hid = aside.hide(visible: true, active: true)
        let first = aside.cancelled()
        let second = aside.cancelled()
        #expect(hid)
        #expect(first == .front)
        #expect(second == nil)
    }

    @Test func editorBehindAnotherAppComesBackBehind() {
        var aside = EditorStepAside()
        let hid = aside.hide(visible: true, active: false)
        let restore = aside.cancelled()
        #expect(hid)
        #expect(restore == .behind)
    }

    @Test func hiddenOrClosedEditorStaysAway() {
        var aside = EditorStepAside()
        let hid = aside.hide(visible: false, active: true)
        let restore = aside.cancelled()
        #expect(!hid)
        #expect(restore == nil)
    }

    @Test func reopeningTheBarKeepsTheFirstState() {
        var aside = EditorStepAside()
        _ = aside.hide(visible: true, active: true)
        let again = aside.hide(visible: false, active: true)
        let restore = aside.cancelled()
        #expect(!again)
        #expect(restore == .front)
    }

    @Test func startedRecordingLeavesTheEditorToTheTakeCard() {
        var aside = EditorStepAside()
        _ = aside.hide(visible: true, active: true)
        aside.started()
        let restore = aside.cancelled()
        #expect(restore == nil)
    }
}
