// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import XCTest
@testable import BitbotCopilot

final class PlotViewportTests: XCTestCase {
    let plot = CGRect(x: 40, y: 20, width: 400, height: 200)
    let full = PlotViewport(x: 100...500, y: -50...50)

    func testSelectionAccountsForAxesAndInvertedY() throws {
        let selected = try XCTUnwrap(full.selecting(from: CGPoint(x: 140, y: 60), to: CGPoint(x: 340, y: 180), in: plot))
        XCTAssertEqual(selected.x.lowerBound, 200, accuracy: 0.00001)
        XCTAssertEqual(selected.x.upperBound, 400, accuracy: 0.00001)
        XCTAssertEqual(selected.y.lowerBound, -30, accuracy: 0.00001)
        XCTAssertEqual(selected.y.upperBound, 30, accuracy: 0.00001)
        XCTAssertEqual(full.selecting(from: CGPoint(x: 340, y: 180), to: CGPoint(x: 140, y: 60), in: plot), selected)
    }

    func testDraggingPastPlotEdgesClampsSelection() throws {
        let selected = try XCTUnwrap(full.selecting(from: CGPoint(x: 240, y: 120), to: CGPoint(x: 1000, y: -100), in: plot))
        XCTAssertEqual(selected.x, 300...500)
        XCTAssertEqual(selected.y, 0...50)
        XCTAssertNil(full.selecting(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 300, y: 100), in: plot))
    }

    func testTinyOrFlatSelectionDoesNotZoom() {
        XCTAssertNil(full.selecting(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 102), in: plot))
        XCTAssertNil(full.selecting(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100), in: plot))
        XCTAssertNil(full.selecting(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 150), in: .zero))
    }

    func testRepeatedZoomUsesCurrentDomainsAndPanPreservesScale() throws {
        let current = PlotViewport(x: 200...400, y: -30...30)
        let next = try XCTUnwrap(current.selecting(from: CGPoint(x: 140, y: 70), to: CGPoint(x: 340, y: 170), in: plot))
        XCTAssertEqual(next, PlotViewport(x: 250...350, y: -15...15))
        let panned = next.panning(from: CGPoint(x: 240, y: 120), to: CGPoint(x: 440, y: 220), in: plot, within: full)
        XCTAssertEqual(panned, PlotViewport(x: 200...300, y: 0...30))
        let clamped = next.panning(from: CGPoint(x: 240, y: 120), to: CGPoint(x: -10000, y: 10000), in: plot, within: full)
        XCTAssertEqual(clamped, PlotViewport(x: 400...500, y: 20...50))
    }
}
