// Copyright (c) 2026 Siyuan Wang.
// Licensed under the GNU General Public License v3. See LICENSE.

import Foundation

struct PlotViewport: Equatable {
    let x: ClosedRange<Double>
    let y: ClosedRange<Double>

    func selecting(from start: CGPoint, to end: CGPoint, in plot: CGRect) -> PlotViewport? {
        guard plot.width > 0, plot.height > 0, plot.contains(start) else { return nil }
        let end = clamped(end, to: plot)
        guard abs(end.x - start.x) >= 6, abs(end.y - start.y) >= 6 else { return nil }
        func xValue(_ pixel: CGFloat) -> Double {
            x.lowerBound + Double((pixel - plot.minX) / plot.width) * (x.upperBound - x.lowerBound)
        }
        func yValue(_ pixel: CGFloat) -> Double {
            y.upperBound - Double((pixel - plot.minY) / plot.height) * (y.upperBound - y.lowerBound)
        }
        let left = xValue(min(start.x, end.x)), right = xValue(max(start.x, end.x))
        let bottom = yValue(max(start.y, end.y)), top = yValue(min(start.y, end.y))
        guard left.isFinite, right.isFinite, bottom.isFinite, top.isFinite, left < right, bottom < top else { return nil }
        return PlotViewport(x: left...right, y: bottom...top)
    }

    func panning(from start: CGPoint, to end: CGPoint, in plot: CGRect, within full: PlotViewport) -> PlotViewport {
        guard plot.width > 0, plot.height > 0 else { return self }
        let dx = -Double((end.x - start.x) / plot.width) * (x.upperBound - x.lowerBound)
        let dy = Double((end.y - start.y) / plot.height) * (y.upperBound - y.lowerBound)
        func shifted(_ range: ClosedRange<Double>, by delta: Double, within bounds: ClosedRange<Double>) -> ClosedRange<Double> {
            let span = min(range.upperBound - range.lowerBound, bounds.upperBound - bounds.lowerBound)
            let lower = min(max(range.lowerBound + delta, bounds.lowerBound), bounds.upperBound - span)
            return lower...(lower + span)
        }
        return PlotViewport(x: shifted(x, by: dx, within: full.x), y: shifted(y, by: dy, within: full.y))
    }

    func clamped(_ point: CGPoint, to plot: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, plot.minX), plot.maxX), y: min(max(point.y, plot.minY), plot.maxY))
    }
}
