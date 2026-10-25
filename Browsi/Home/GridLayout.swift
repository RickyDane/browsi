import Foundation

/// A rectangle on the home grid, in cells.
nonisolated struct GridRect: Equatable, Hashable, Sendable, Codable {
    var col: Int
    var row: Int
    var w: Int
    var h: Int

    func intersects(_ o: GridRect) -> Bool {
        col < o.col + o.w && o.col < col + w && row < o.row + o.h && o.row < row + h
    }
}

/// Dashboard layout rules (pure, unit tested):
/// the item being moved/resized keeps its place, anything it overlaps is pushed down,
/// then everything floats up to close gaps (vertical compaction).
nonisolated enum GridLayout {
    static let columns = 12
    static let minSize = (w: 2, h: 2)
    static let maxH = 14

    static func clamp(_ r: GridRect, columns: Int = columns) -> GridRect {
        var r = r
        r.w = min(max(r.w, minSize.w), columns)
        r.h = min(max(r.h, minSize.h), maxH)
        r.col = min(max(r.col, 0), columns - r.w)
        r.row = max(r.row, 0)
        return r
    }

    /// Returns new rects for all items with `fixedID` placed at `fixed`.
    /// `locked` rects (e.g. the home search area) never move and nothing may overlap them.
    static func resolve<ID: Hashable>(_ items: [(id: ID, rect: GridRect)], fixedID: ID?, fixed: GridRect?,
                                      locked: [GridRect] = [], columns: Int = columns) -> [ID: GridRect] {
        var placed: [(ID, GridRect)] = []
        if let fixedID, var fixed {
            fixed = clamp(fixed, columns: columns)
            while locked.contains(where: { $0.intersects(fixed) }) { fixed.row += 1 }
            placed.append((fixedID, fixed))
        }
        let others = items.filter { $0.id != fixedID }
            .sorted { ($0.rect.row, $0.rect.col) < ($1.rect.row, $1.rect.col) }
        for item in others {
            var r = clamp(item.rect, columns: columns)
            while placed.contains(where: { $0.1.intersects(r) }) || locked.contains(where: { $0.intersects(r) }) { r.row += 1 }
            placed.append((item.id, r))
        }
        // Compact upwards, top to bottom (the fixed item compacts too, so it can't float in a gap).
        var result: [ID: GridRect] = [:]
        var settled: [GridRect] = locked
        for (id, rect) in placed.sorted(by: { ($0.1.row, $0.1.col) < ($1.1.row, $1.1.col) }) {
            var r = rect
            while r.row > 0 {
                var up = r; up.row -= 1
                if settled.contains(where: { $0.intersects(up) }) { break }
                r = up
            }
            settled.append(r)
            result[id] = r
        }
        return result
    }

    /// First free spot of size w×h scanning rows top-down.
    static func firstFree(w: Int, h: Int, among rects: [GridRect], columns: Int = columns) -> GridRect {
        var row = 0
        while true {
            for col in 0...(columns - w) {
                let r = GridRect(col: col, row: row, w: w, h: h)
                if !rects.contains(where: { $0.intersects(r) }) { return r }
            }
            row += 1
        }
    }
}
