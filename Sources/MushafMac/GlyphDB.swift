import Foundation
import SQLite3

/// One word (or ayah-end marker) on a page image, in 1024px image coordinates.
struct Glyph {
    let key: AyahKey
    let position: Int   // word index within the ayah, 1-based; the last one is the ayah-end marker
    let line: Int
    let rect: CGRect
}

/// Read-only access to ayahinfo_1024.db: word bounding boxes for all 604 pages.
final class GlyphDB {
    private var db: OpaquePointer?
    private var pageCache: [Int: [Glyph]] = [:]
    private(set) var ayahCounts: [Int] = Array(repeating: 0, count: 115)

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw NSError(domain: "GlyphDB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open \(url.lastPathComponent)"])
        }
        query("SELECT sura_number, MAX(ayah_number) FROM glyphs GROUP BY sura_number") { stmt in
            let sura = Int(sqlite3_column_int(stmt, 0))
            if (1...114).contains(sura) { self.ayahCounts[sura] = Int(sqlite3_column_int(stmt, 1)) }
        }
    }

    deinit { sqlite3_close(db) }

    func glyphs(page: Int) -> [Glyph] {
        if let cached = pageCache[page] { return cached }
        var result: [Glyph] = []
        query("""
            SELECT sura_number, ayah_number, line_number, position, min_x, max_x, min_y, max_y
            FROM glyphs WHERE page_number = ? ORDER BY glyph_id
            """, bind: [page]) { s in
            let x0 = Double(sqlite3_column_int(s, 4)), x1 = Double(sqlite3_column_int(s, 5))
            let y0 = Double(sqlite3_column_int(s, 6)), y1 = Double(sqlite3_column_int(s, 7))
            result.append(Glyph(
                key: AyahKey(Int(sqlite3_column_int(s, 0)), Int(sqlite3_column_int(s, 1))),
                position: Int(sqlite3_column_int(s, 3)),
                line: Int(sqlite3_column_int(s, 2)),
                rect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)))
        }
        pageCache[page] = result
        return result
    }

    /// Ayahs on a page, in reading order.
    func ayahs(page: Int) -> [AyahKey] {
        var seen = Set<AyahKey>()
        return glyphs(page: page).map(\.key).filter { seen.insert($0).inserted }
    }

    /// Glyphs the ayah has across all pages (words, pause marks and its end marker).
    func glyphTotal(_ key: AyahKey) -> Int {
        var n = 0
        query("SELECT COUNT(*) FROM glyphs WHERE sura_number = ? AND ayah_number = ?", bind: [key.sura, key.ayah]) { s in
            n = Int(sqlite3_column_int(s, 0))
        }
        return n
    }

    func page(of key: AyahKey) -> Int? {
        var page: Int?
        query("SELECT MIN(page_number) FROM glyphs WHERE sura_number = ? AND ayah_number = ?",
              bind: [key.sura, key.ayah]) { s in
            if sqlite3_column_type(s, 0) != SQLITE_NULL { page = Int(sqlite3_column_int(s, 0)) }
        }
        return page
    }

    /// One rectangle per line the ayah covers on this page (words on a line merged).
    func highlightRects(for key: AyahKey, page: Int) -> [CGRect] {
        var byLine: [Int: CGRect] = [:]
        for g in glyphs(page: page) where g.key == key {
            byLine[g.line] = byLine[g.line].map { $0.union(g.rect) } ?? g.rect
        }
        return byLine.keys.sorted().map { byLine[$0]! }
    }

    func ayah(at point: CGPoint, page: Int) -> AyahKey? {
        let glyphs = glyphs(page: page)
        if let hit = glyphs.first(where: { $0.rect.insetBy(dx: -4, dy: -10).contains(point) }) {
            return hit.key
        }
        // Gaps between words: take the nearest glyph on the line under the cursor.
        let onLine = glyphs.filter { point.y >= $0.rect.minY - 12 && point.y <= $0.rect.maxY + 12 }
        return onLine.min(by: { abs($0.rect.midX - point.x) < abs($1.rect.midX - point.x) })?.key
    }

    func next(after key: AyahKey) -> AyahKey? {
        if key.ayah < ayahCounts[key.sura] { return AyahKey(key.sura, key.ayah + 1) }
        return key.sura < 114 ? AyahKey(key.sura + 1, 1) : nil
    }

    func previous(before key: AyahKey) -> AyahKey? {
        if key.ayah > 1 { return AyahKey(key.sura, key.ayah - 1) }
        return key.sura > 1 ? AyahKey(key.sura - 1, ayahCounts[key.sura - 1]) : nil
    }

    private func query(_ sql: String, bind: [Int] = [], row: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        for (i, value) in bind.enumerated() { sqlite3_bind_int(stmt, Int32(i + 1), Int32(value)) }
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }
}
