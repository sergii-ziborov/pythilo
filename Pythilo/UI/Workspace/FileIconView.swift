import SwiftUI

/// The file type tile from the design's token board.
struct FileIconView: View {
    let name: String
    var isDirectory = false
    var isOpen = false

    private struct Tile {
        let glyph: String
        let back: UInt32
        let front: UInt32
    }

    private var tile: Tile {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        if lower == "__init__.py" { return Tile(glyph: "in", back: 0x2B2A18, front: 0xD8C76A) }
        if lower == "manage.py" { return Tile(glyph: "mg", back: 0x1F3F66, front: 0x8CC4FF) }
        if ext == "py", lower.hasPrefix("test_") || lower.hasSuffix("_test.py") || lower == "conftest.py" {
            return Tile(glyph: "ts", back: 0x123529, front: 0x5FD6A8)
        }
        if lower.hasPrefix("requirements") && ext == "txt" { return Tile(glyph: "rq", back: 0x3A2C12, front: 0xF2C25A) }
        if lower.hasPrefix(".git") { return Tile(glyph: "gi", back: 0x3A1E18, front: 0xFF8A65) }
        if lower.hasPrefix(".env") { return Tile(glyph: "en", back: 0x2A2F38, front: 0xFFD43B) }
        switch ext {
        case "py", "pyi": return Tile(glyph: "py", back: 0x3A3210, front: 0xFFD43B)
        case "ipynb": return Tile(glyph: "nb", back: 0x3A2412, front: 0xF2A65A)
        case "csv", "tsv": return Tile(glyph: ",,", back: 0x123529, front: 0x7BDCB5)
        case "json": return Tile(glyph: "{}", back: 0x10302F, front: 0x5ED3D3)
        case "toml", "cfg", "ini", "yaml", "yml": return Tile(glyph: "tm", back: 0x2A2F38, front: 0xC9D2DC)
        case "md", "markdown", "rst": return Tile(glyph: "md", back: 0x2A2240, front: 0xB79CFF)
        case "html", "htm": return Tile(glyph: "<>", back: 0x3A1E18, front: 0xFF9A72)
        case "css": return Tile(glyph: "#", back: 0x16263A, front: 0x6CB6FF)
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic": return Tile(glyph: "im", back: 0x32203A, front: 0xE0A0F0)
        case "sqlite3", "sqlite", "db": return Tile(glyph: "db", back: 0x1E2C3A, front: 0x9CC4E8)
        default: return Tile(glyph: "tx", back: 0x232A33, front: 0x9AA6B4)
        }
    }

    var body: some View {
        if isDirectory {
            Image(systemName: isOpen ? "folder.fill" : "folder.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color(uiColor: UIColor(hex: isOpen ? 0x8CC4FF : 0x5AA9FF)))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        } else {
            Text(tile.glyph)
                .font(.system(size: tile.glyph.count > 1 ? 11 : 14, weight: .heavy, design: .monospaced))
                .kerning(-0.4)
                .foregroundStyle(Color(uiColor: UIColor(hex: tile.front)))
                .frame(width: 24, height: 24)
                .background(Color(uiColor: UIColor(hex: tile.back)), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}
