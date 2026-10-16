import SwiftUI
import AppKit

// MARK: - 5x7 LED font (classic HD44780-style). Each glyph: 7 rows, bit 4 = leftmost.

enum DotFont {
    static let glyphs: [Character: [UInt8]] = [
        "A": [0x0E, 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11],
        "B": [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
        "C": [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
        "D": [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C],
        "E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
        "F": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
        "G": [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
        "H": [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        "I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
        "J": [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
        "K": [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
        "L": [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
        "M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
        "N": [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
        "O": [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        "P": [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
        "Q": [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
        "R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
        "S": [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
        "T": [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
        "U": [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        "V": [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
        "W": [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A],
        "X": [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
        "Y": [0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04],
        "Z": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
        "0": [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
        "1": [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
        "2": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
        "3": [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
        "4": [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
        "5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
        "6": [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
        "7": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
        "8": [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
        "9": [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
        " ": [0, 0, 0, 0, 0, 0, 0],
        ".": [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
        ",": [0x00, 0x00, 0x00, 0x00, 0x0C, 0x04, 0x08],
        ":": [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],
        ";": [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x04, 0x08],
        "-": [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
        "/": [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x00],
        "'": [0x0C, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00],
        "\"": [0x0A, 0x0A, 0x0A, 0x00, 0x00, 0x00, 0x00],
        "&": [0x0C, 0x12, 0x14, 0x08, 0x15, 0x12, 0x0D],
        "(": [0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02],
        ")": [0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08],
        "!": [0x04, 0x04, 0x04, 0x04, 0x00, 0x00, 0x04],
        "?": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04],
        "+": [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00],
        "=": [0x00, 0x00, 0x1F, 0x00, 0x1F, 0x00, 0x00],
        "#": [0x0A, 0x0A, 0x1F, 0x0A, 0x1F, 0x0A, 0x0A],
        "@": [0x0E, 0x11, 0x01, 0x0D, 0x15, 0x15, 0x0E],
        "*": [0x00, 0x04, 0x15, 0x0E, 0x15, 0x04, 0x00],
        "%": [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03],
        "$": [0x04, 0x0F, 0x14, 0x0E, 0x05, 0x1E, 0x04],
        ">": [0x08, 0x04, 0x02, 0x01, 0x02, 0x04, 0x08],
        "<": [0x02, 0x04, 0x08, 0x10, 0x08, 0x04, 0x02],
        "•": [0x00, 0x0E, 0x1F, 0x1F, 0x1F, 0x0E, 0x00],
    ]

    static let replacements: [Character: Character] = [
        "’": "'", "‘": "'", "“": "\"", "”": "\"", "–": "-", "—": "-", "…": ".",
    ]

    static func normalize(_ s: String) -> [Character] {
        s.uppercased().compactMap { ch in
            let c = replacements[ch] ?? ch
            if glyphs[c] != nil { return c }
            return c.isWhitespace ? " " : nil
        }
    }

    /// Column bitmasks (bit 0 = top row) for a string; 5 columns per glyph + 1 spacing column.
    static func columns(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        for ch in normalize(s) {
            let g = glyphs[ch]!
            for c in 0..<5 {
                var m: UInt8 = 0
                for r in 0..<7 where g[r] & (0x10 >> c) != 0 { m |= 1 << r }
                out.append(m)
            }
            out.append(0)
        }
        if !out.isEmpty { out.removeLast() }
        return out
    }

    static func width(_ s: String) -> Int { max(0, normalize(s).count * 6 - 1) }
}

// MARK: - Frame buffer

/// A grid of LEDs; each cell holds a palette index (0 = off).
struct LEDFrame {
    let cols: Int
    let rows: Int
    var px: [UInt8]

    init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        px = Array(repeating: 0, count: cols * rows)
    }

    mutating func set(_ x: Int, _ y: Int, _ c: UInt8) {
        guard x >= 0, x < cols, y >= 0, y < rows else { return }
        px[y * cols + x] = c
    }

    mutating func blit(_ columns: [UInt8], x: Int, y: Int, color: UInt8) {
        for (i, m) in columns.enumerated() where m != 0 {
            for r in 0..<7 where m & (1 << r) != 0 { set(x + i, y + r, color) }
        }
    }

    mutating func text(_ s: String, x: Int, y: Int, color: UInt8, rightAligned: Bool = false) {
        let cols = DotFont.columns(s)
        blit(cols, x: rightAligned ? x - cols.count : x, y: y, color: color)
    }

    /// Round "bullet" in one or two line colours, like the route markers on the map.
    mutating func lineMarker(x: Int, y: Int, colors: [UInt8]) {
        let g: [UInt8] = [0x0E, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x0E]
        for c in 0..<5 {
            for r in 0..<7 where g[r] & (0x10 >> c) != 0 {
                // Two-line services: split down the middle, centre column split top/bottom.
                let color = colors.count > 1 ? (c < 2 || (c == 2 && r < 3) ? colors[0] : colors[1]) : (colors.first ?? 1)
                set(x + c, y + r, color)
            }
        }
    }
}

// MARK: - Rendering

let ledAmber = Color(red: 1.0, green: 0.62, blue: 0.08)

/// Draws a frame as physical LEDs: dim unlit dots, slightly uneven lit dots, and a soft bloom.
struct LEDCanvas: View {
    let frame: LEDFrame
    let palette: [Color]   // index 0 unused
    var pitch: CGFloat = 2.6

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, _ in
            let d = pitch * 0.74
            let inset = (pitch - d) / 2
            var off = Path()
            var lit: [[Path]] = Array(repeating: Array(repeating: Path(), count: 3), count: palette.count)
            for y in 0..<frame.rows {
                for x in 0..<frame.cols {
                    let r = CGRect(x: CGFloat(x) * pitch + inset, y: CGFloat(y) * pitch + inset, width: d, height: d)
                    let c = Int(frame.px[y * frame.cols + x])
                    if c == 0 {
                        off.addEllipse(in: r)
                    } else {
                        // Old panels never have perfectly even LEDs.
                        let h = ((x &* 73856093) ^ (y &* 19349663)) & 0xFF
                        lit[c][h < 200 ? 0 : (h < 235 ? 1 : 2)].addEllipse(in: r)
                    }
                }
            }
            ctx.fill(off, with: .color(Color(red: 0.32, green: 0.18, blue: 0.06).opacity(0.28)))

            ctx.drawLayer { g in
                g.addFilter(.blur(radius: pitch * 1.1))
                for c in 1..<palette.count {
                    for p in lit[c] { g.fill(p, with: .color(palette[c].opacity(0.55))) }
                }
            }
            let levels: [Double] = [1.0, 0.82, 0.62]
            for c in 1..<palette.count {
                for (i, p) in lit[c].enumerated() {
                    ctx.fill(p, with: .color(palette[c].opacity(levels[i])))
                }
            }
        }
        .frame(width: CGFloat(frame.cols) * pitch, height: CGFloat(frame.rows) * pitch)
    }
}

/// The black module behind the LEDs, with a faint glass sheen and grain.
struct LEDModule<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(5.4)
            .background(Color(red: 0.03, green: 0.025, blue: 0.02))
            .overlay(Noise.image.resizable(resizingMode: .tile).opacity(0.07).blendMode(.screen).allowsHitTesting(false))
            .overlay(
                LinearGradient(colors: [.white.opacity(0.06), .clear, .clear], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.black, lineWidth: 2))
            .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
    }
}

enum Noise {
    static let image: Image = {
        let n = 96
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(n * n) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(truncatingIfNeeded: seed >> 56)
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v; bytes[i * 4 + 3] = 255
        }
        let cg = CGContext(data: &bytes, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return Image(decorative: cg, scale: 2)
    }()
}
