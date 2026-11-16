import SwiftUI

/// Span of a tile in grid cells; set with `.tileSize(_:)`.
struct TileSpanKey: LayoutValueKey {
    static let defaultValue: TileSize = .small
}

extension View {
    func tileSize(_ size: TileSize) -> some View { layoutValue(key: TileSpanKey.self, value: size) }
}

/// Packs widgets on a board of near-square cells, each tile spanning 1×1 … 4×3 cells, placed
/// first-fit in reading order. `fit` sizes the cells so a board fills the screen exactly, like a
/// hardware deck: 6 × 4 cells in landscape and 4 × 7 in portrait. More rows than that scroll.
struct DashboardGrid: Layout {
    var columns: Int
    var rowHeight: CGFloat
    var spacing: CGFloat = Fluent.gutter

    struct Placement {
        var columns = 1
        var frames: [CGRect] = []
        var height: CGFloat = 0
    }

    /// Columns and row height for a board shown in `size`.
    static func fit(_ size: CGSize, spacing: CGFloat = Fluent.gutter) -> (columns: Int, rowHeight: CGFloat) {
        if size.width < 600 { // iPhone: two columns that scroll
            return (2, max(120, (size.width - spacing) / 2 * 0.95))
        }
        let landscape = size.width > size.height
        let rows: CGFloat = landscape ? 4 : 7
        let height = ((size.height - (rows - 1) * spacing) / rows).rounded(.down)
        return (landscape ? 6 : 4, max(120, height))
    }

    func place(width: CGFloat, spans: [TileSize]) -> Placement {
        let cols = max(1, columns)
        let cell = max(1, (width - CGFloat(cols - 1) * spacing) / CGFloat(cols))
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
