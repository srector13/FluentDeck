import SwiftUI

/// Span of a tile in grid cells; set with `.tileSize(_:)`.
struct TileSpanKey: LayoutValueKey {
    static let defaultValue: TileSize = .small
}

extension View {
    func tileSize(_ size: TileSize) -> some View { layoutValue(key: TileSpanKey.self, value: size) }
}

/// Packs widgets like the Windows 11 widget board: a grid of square-ish cells, each tile spanning
/// 1×1 … 4×2 cells, placed first-fit in reading order. Column count adapts to the width
/// (6 on an 11" iPad in landscape, 4 in portrait), so any number of panels flows naturally.
struct DashboardGrid: Layout {
    var minCell: CGFloat = 168
    var spacing: CGFloat = Fluent.gutter

    struct Placement {
        var columns = 1
        var frames: [CGRect] = []
        var height: CGFloat = 0
    }

    func columns(for width: CGFloat) -> Int {
        max(2, Int((width + spacing) / (minCell + spacing)))
    }

    func place(width: CGFloat, spans: [TileSize]) -> Placement {
        let cols = columns(for: width)
        let cell = (width - CGFloat(cols - 1) * spacing) / CGFloat(cols)
        let rowHeight = min(max(cell * 0.92, 150), 230)
        var occupied: [[Bool]] = []
        var frames: [CGRect] = []

        func fits(_ r: Int, _ c: Int, _ w: Int, _ h: Int) -> Bool {
            guard c + w <= cols else { return false }
            for rr in r..<(r + h) {
                if rr >= occupied.count { continue }
                for cc in c..<(c + w) where occupied[rr][cc] { return false }
            }
            return true
        }

        for size in spans {
            let w = min(size.span.columns, cols)
            let h = size.span.rows
            var row = 0, col = 0
            search: while true {
                for c in 0..<cols where fits(row, c, w, h) { col = c; break search }
                row += 1
            }
            while occupied.count < row + h { occupied.append(Array(repeating: false, count: cols)) }
            for rr in row..<(row + h) { for cc in col..<(col + w) { occupied[rr][cc] = true } }
            frames.append(CGRect(
                x: CGFloat(col) * (cell + spacing),
                y: CGFloat(row) * (rowHeight + spacing),
                width: CGFloat(w) * cell + CGFloat(w - 1) * spacing,
                height: CGFloat(h) * rowHeight + CGFloat(h - 1) * spacing))
        }
        let rows = occupied.count
        return Placement(columns: cols, frames: frames, height: rows == 0 ? 0 : CGFloat(rows) * (rowHeight + spacing) - spacing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 1024
        let p = place(width: width, spans: subviews.map { $0[TileSpanKey.self] })
        return CGSize(width: width, height: p.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = place(width: bounds.width, spans: subviews.map { $0[TileSpanKey.self] })
        for (i, sub) in subviews.enumerated() {
            let f = p.frames[i]
            sub.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                      anchor: .topLeading,
                      proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}
