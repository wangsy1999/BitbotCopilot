// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import AppKit
import GameController
import Observation
import BitbotCore

@MainActor @Observable
final class InputController {
    private(set) var enabled = false { didSet { if !enabled && oldValue { releaseAll() } } }
    private(set) var controllerName = "未连接手柄"
    private(set) var activeKeys: Set<String> = []
    @ObservationIgnored private weak var connection: RobotConnection?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var previous: [String: Int64] = [:]
    @ObservationIgnored private var held: Set<String> = []
    @ObservationIgnored private var heldKeys: [UInt16: (String, String)] = [:]
    @ObservationIgnored private var revision: UUID?
    @ObservationIgnored private var activityObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let applicationIsActive: @MainActor () -> Bool

    init(applicationIsActive: @escaping @MainActor () -> Bool = { NSApp.isActive }) {
        self.applicationIsActive = applicationIsActive
    }

    func start(_ connection: RobotConnection) {
        stop(); self.connection = connection; revision = connection.sessionID
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            activityObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAvailability() }
            })
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.keyboard(event) ?? false }
            return consumed ? nil : event
        }
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        refreshAvailability(focus: true)
    }
    func stop() {
        enabled = false
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        timer?.invalidate(); timer = nil; connection = nil
        activityObservers.forEach { NotificationCenter.default.removeObserver($0) }
        activityObservers = []
    }
    func keyboard(_ event: NSEvent) -> Bool {
        refreshAvailability()
        if event.type == .keyUp, let (name, key) = heldKeys.removeValue(forKey: event.keyCode) {
            held.remove(name); activeKeys.remove(key); send([name: .integer(2)]); return true
        }
        guard enabled, connection?.isConnected == true,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              event.window?.attachedSheet == nil,
              !Self.isEditingText(in: event.window ?? NSApp.keyWindow),
              let key = event.charactersIgnoringModifiers?.lowercased(),
              let control = connection?.controls.first(where: { $0.kb_key.lowercased() == key }) else { return false }
        if event.isARepeat { return true }
        if event.type == .keyDown {
            held.insert(control.event); activeKeys.insert(key); heldKeys[event.keyCode] = (control.event, key)
        }
        else { held.remove(control.event); activeKeys.remove(key) }
        send([control.event: .integer(event.type == .keyDown ? 1 : 2)])
        return true
    }
    private func poll() {
        // Re-evaluate before the early return, so a pause can never latch permanently.
        refreshAvailability()
        let pad = GCController.controllers().first
        controllerName = pad?.vendorName ?? "未连接手柄"
        guard enabled else { return }
        guard let p = pad?.extendedGamepad else {
            if !previous.isEmpty { releaseGamepad() }; return
        }
        var current: [String: Int64] = [:]
        let buttons: [(String, GCControllerButtonInput?)] = [
            ("GAMEPAD_BUTTON_A", p.buttonA), ("GAMEPAD_BUTTON_B", p.buttonB),
            ("GAMEPAD_BUTTON_X", p.buttonX), ("GAMEPAD_BUTTON_Y", p.buttonY),
            ("GAMEPAD_BUTTON_LB", p.leftShoulder), ("GAMEPAD_BUTTON_RB", p.rightShoulder),
            ("GAMEPAD_BUTTON_MENU", p.buttonMenu), ("GAMEPAD_BUTTON_SWITCH", p.buttonOptions),
            ("GAMEPAD_BUTTON_XBOX", p.buttonHome),
            ("GAMEPAD_BUTTON_L_STICK", p.leftThumbstickButton), ("GAMEPAD_BUTTON_R_STICK", p.rightThumbstickButton),
            ("GAMEPAD_HAT_UP", p.dpad.up), ("GAMEPAD_HAT_DOWN", p.dpad.down),
            ("GAMEPAD_HAT_LEFT", p.dpad.left), ("GAMEPAD_HAT_RIGHT", p.dpad.right)
        ]
        for (key, button) in buttons { current[key] = button?.isPressed == true ? 1 : 2 }
        let axes: [(String, Float)] = [
            ("GAMEPAD_JOYSTICK_LX", -p.leftThumbstick.xAxis.value),
            ("GAMEPAD_JOYSTICK_LY", p.leftThumbstick.yAxis.value),
            ("GAMEPAD_JOYSTICK_RX", -p.rightThumbstick.xAxis.value),
            ("GAMEPAD_JOYSTICK_RY", p.rightThumbstick.yAxis.value),
            ("GAMEPAD_JOYSTICK_LT", p.leftTrigger.value), ("GAMEPAD_JOYSTICK_RT", p.rightTrigger.value)
        ]
        for (key, value) in axes { current[key] = Int64((abs(value) < 0.02 ? 0 : value) * 32768) }
        var events: [String: CommandValue] = [:]
        for (key, value) in current where previous[key] != value {
            if let event = connection?.controls.first(where: { $0.kb_key == key })?.event { events[event] = .integer(value) }
        }
        previous = current; send(events)
    }
    func joystick(x: Double, y: Double, right: Bool) {
        refreshAvailability()
        guard enabled else { return }
        let prefix = right ? "GAMEPAD_JOYSTICK_R" : "GAMEPAD_JOYSTICK_L"
        var events: [String: CommandValue] = [:]
        for (key, value) in [(prefix + "X", x), (prefix + "Y", y)] {
            if let event = connection?.controls.first(where: { $0.kb_key == key })?.event {
                events[event] = .integer(Int64(value * 32768))
            }
        }
        send(events)
    }
    private func releaseGamepad() {
        var events: [String: CommandValue] = [:]
        for key in previous.keys {
            if let event = connection?.controls.first(where: { $0.kb_key == key })?.event {
                events[event] = .integer(key.contains("JOYSTICK") ? 0 : 2)
            }
        }
        previous = [:]; send(events)
    }
    private func releaseAll() {
        send(Dictionary(uniqueKeysWithValues: held.map { ($0, .integer(2)) }))
        held = []; heldKeys = [:]; activeKeys = []; releaseGamepad()
        joystickRelease()
    }
    private func joystickRelease() {
        var events: [String: CommandValue] = [:]
        for key in ["GAMEPAD_JOYSTICK_LX", "GAMEPAD_JOYSTICK_LY", "GAMEPAD_JOYSTICK_RX", "GAMEPAD_JOYSTICK_RY"] {
            if let event = connection?.controls.first(where: { $0.kb_key == key })?.event { events[event] = .integer(0) }
        }
        send(events)
    }
    private func send(_ events: [String: CommandValue]) {
        guard !events.isEmpty, let connection, connection.isConnected else { return }
        let token = connection.sessionID
        guard revision == token else { return }
        Task {
            guard connection.sessionID == token else { return }
            do { try await connection.send(events) } catch { connection.error = error.localizedDescription }
        }
    }
    static func isEditingText(in window: NSWindow?) -> Bool {
        if let editor = window?.firstResponder as? NSTextView { return editor.isEditable }
        if let field = window?.firstResponder as? NSTextField { return field.isEditable }
        return false
    }

    func focusControls(in window: NSWindow? = nil) {
        let window = window ?? NSApp.keyWindow
        window?.endEditing(for: nil)
        window?.makeFirstResponder(nil)
    }

    func updateAvailability(isActive: Bool, focus: Bool = false) {
        if revision != connection?.sessionID { enabled = false }
        guard isActive, connection?.isConnected == true else {
            enabled = false
            return
        }
        revision = connection?.sessionID
        enabled = true
        if focus { focusControls() }
    }

    func refreshAvailability(focus: Bool = false) {
        updateAvailability(isActive: applicationIsActive(), focus: focus)
    }
}
