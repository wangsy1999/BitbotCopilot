// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import AppKit
import XCTest
@testable import BitbotCopilot

final class InputFocusTests: XCTestCase {
    @MainActor func testEnablingControlsEndsAddressFieldEditing() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 250, height: 24))
        window.contentView?.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertTrue(InputController.isEditingText(in: window))
        let input = InputController()
        input.focusControls(in: window)
        XCTAssertFalse(InputController.isEditingText(in: window))
        // Returning to the address field must still allow ordinary typing.
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertTrue(InputController.isEditingText(in: window))
    }

    @MainActor func testReadOnlyOutputDoesNotSuppressRobotKeyboard() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        text.isEditable = false
        window.contentView?.addSubview(text)
        XCTAssertTrue(window.makeFirstResponder(text))
        XCTAssertFalse(InputController.isEditingText(in: window))
        text.isEditable = true
        XCTAssertTrue(InputController.isEditingText(in: window))
    }
}
