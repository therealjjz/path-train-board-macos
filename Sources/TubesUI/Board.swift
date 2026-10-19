import SwiftUI
import TubesFeed

extension Color {
    public init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: .whitespaces), radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - Board layout

/// Platform-sign layout. 210 LED columns fits "JOURNAL SQUARE VIA HOBOKEN  45 MIN".
public let boardCols = 210
/// Narrower layout for phones: bigger LEDs, with sign-style abbreviations so names fit.
public let compactBoardCols = 140

/// Abbreviations as used on PATH signage, for the compact board.
public func abbreviatedSignText(_ s: String) -> String {
    var t = s.uppercased()
    for (long, short) in [("WORLD TRADE CENTER", "WORLD TRADE CTR"), ("JOURNAL SQUARE", "JOURNAL SQ"),
                          ("EXCHANGE PLACE", "EXCHANGE PL"), ("VIA HOBOKEN", "VIA HOB"),
                          ("STREET", "ST")] {
        t = t.replacingOccurrences(of: long, with: short)
    }
    return t
}
public let maxTrainsPerDirection = 3

/// A train line on the board, so taps can be mapped back to the train.
public struct BoardRow: Sendable {
    public let y: Int                 // top LED row
    public let direction: String
    public let message: Message
}

/// Palette indices: 1 = amber, 2 = dim amber, 3+ = line colours.
public struct BoardFrame {
    public var frame: LEDFrame
    public var palette: [Color]
    public var rows: [BoardRow]
}

/// Height in LEDs of a full board (fixed so the view doesn't jump between stations).
public let boardRows = 7 + 2 * (13 + 9 * maxTrainsPerDirection)

/// `highlight` draws the matching train with a bracket, used while it is being tracked.
public func makeBoard(station: String, dests: [Destination], loaded: Bool, now: Date,
                      cols boardCols: Int = boardCols,
                      highlight: ((String, Message) -> Bool)? = nil) -> BoardFrame {
    var palette: [Color] = [.clear, ledAmber, ledAmber.opacity(0.55)]
    var lineIndex: [String: UInt8] = [:]
    func colorIndex(_ hex: String) -> UInt8 {
        if let i = lineIndex[hex] { return i }
        palette.append(Color(hex: hex))
        lineIndex[hex] = UInt8(palette.count - 1)
        return lineIndex[hex]!
    }

    let sections = dests.isEmpty ? [nil] : dests.map { Optional($0) }
    var f = LEDFrame(cols: boardCols, rows: boardRows)
    var rows: [BoardRow] = []

    let clock = DateFormatter()
    clock.timeZone = TimeZone(identifier: "America/New_York")
    clock.dateFormat = "h:mm a"
    let short = boardCols < 200
    f.text(short ? abbreviatedSignText(stationName(station)) : stationName(station), x: 0, y: 0, color: 1)
    f.text(clock.string(from: now), x: boardCols, y: 0, color: 1, rightAligned: true)

    var y = 7
    for (i, d) in sections.enumerated() {
        // Each direction owns a fixed block, so lines don't shift when a train drops off.
        y = 7 + i * (13 + 9 * maxTrainsPerDirection) + 2
        // Thin rule between header and each direction block.
        for x in stride(from: 0, to: boardCols, by: 2) { f.set(x, y - 1, 2) }
        y += 2
        guard let d else {
            f.text(loaded ? "NO REAL-TIME DATA" : "PLEASE WAIT...", x: 0, y: y, color: 1)
            y += 9
            continue
        }
        f.text(d.label == "ToNY" ? "TO NEW YORK" : "TO NEW JERSEY", x: 0, y: y, color: 2)
        y += 9
        if d.messages.isEmpty {
            f.text("NO TRAINS SCHEDULED", x: 8, y: y, color: 1)
            y += 9
        }
        for m in d.messages.prefix(maxTrainsPerDirection) {
            rows.append(BoardRow(y: y, direction: d.label, message: m))
            f.lineMarker(x: 0, y: y, colors: m.hexColors.map(colorIndex))
            let time = m.arrivalTimeMessage
            let timeW = DotFont.width(time)
            var sign = short ? abbreviatedSignText(m.headSign) : m.headSign
            while DotFont.width(sign) > boardCols - 8 - timeW - 6 && !sign.isEmpty { sign.removeLast() }
            f.text(sign, x: 8, y: y, color: 1)
            f.text(time, x: boardCols, y: y, color: 1, rightAligned: true)
            if highlight?(d.label, m) == true {
                // Dim underline beneath the tracked train.
                for x in stride(from: 8, to: boardCols, by: 1) { f.set(x, y + 8, 2) }
            }
            y += 9
        }
    }
    return BoardFrame(frame: f, palette: palette, rows: rows)
}

// MARK: - Shared views

/// Scrolling alert strip; steps one LED column at a time like a real sign.
public struct Ticker: View {
    let text: String
    var pitch: CGFloat
    var cols = boardCols
    private let speed = 28.0   // LED columns per second

    public init(text: String, pitch: CGFloat, cols: Int = boardCols) {
        self.text = text
        self.pitch = pitch
        self.cols = cols
    }

    public var body: some View {
        let glyphs = DotFont.columns(text)
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let span = glyphs.count + cols
            let step = Int(ctx.date.timeIntervalSinceReferenceDate * speed) % max(1, span)
            var f = LEDFrame(cols: cols, rows: 7)
            f.blit(glyphs, x: cols - step, y: 0, color: 1)
            return LEDCanvas(frame: f, palette: [.clear, ledAmber], pitch: pitch)
        }
    }
}

/// Little indicator LED on the housing: green when synced, red when the feed is unreachable.
public struct StatusLamp: View {
    @ObservedObject var store: BoardStore
    public init(store: BoardStore) { self.store = store }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let age = store.fetchedAt.map { Int(ctx.date.timeIntervalSince($0)) }
            let ok = store.error == nil && (age ?? 99) < 30
            HStack(spacing: 5) {
                Text(store.error ?? (age.map { "LIVE · \($0)s" } ?? "…"))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Circle()
                    .fill(ok ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                    .shadow(color: ok ? .green : .red, radius: 3)
            }
        }
    }
}

/// Brushed dark-metal casing with corner screws.
public struct Housing: View {
    var cornerRadius: CGFloat = 10
    public init(cornerRadius: CGFloat = 10) { self.cornerRadius = cornerRadius }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
            Noise.image.resizable(resizingMode: .tile)
                .opacity(0.05)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            GeometryReader { g in
                ForEach(0..<4, id: \.self) { i in
                    Screw().position(x: i % 2 == 0 ? 6 : g.size.width - 6, y: i < 2 ? 6 : g.size.height - 6)
                }
            }
        }
    }
}

struct Screw: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.45), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(.black.opacity(0.6)).frame(width: 4, height: 0.8).rotationEffect(.degrees(35))
        }
        .frame(width: 5, height: 5)
    }
}

/// Round line-colour dot; two-line services are split down the middle.
public struct LineDot: View {
    let hex: [String]
    var size: CGFloat = 7
    public init(hex: [String], size: CGFloat = 7) {
        self.hex = hex
        self.size = size
    }

    public var body: some View {
        let colors = hex.map(Color.init(hex:))
        ZStack {
            if colors.count > 1 {
                Circle().trim(from: 0, to: 0.5).fill(colors[0]).rotationEffect(.degrees(90))
                Circle().trim(from: 0.5, to: 1).fill(colors[1]).rotationEffect(.degrees(90))
            } else {
                Circle().fill(colors.first ?? .gray)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Store

/// Polls the departures feed (8 s) and alerts (5 min) while alive.
@MainActor
public final class BoardStore: ObservableObject {
    @Published public private(set) var departures: Departures?
    @Published public private(set) var serviceAlerts: [ServiceAlert] = []
    @Published public private(set) var alertsFetchedAt: Date?
    public var alerts: [String] { serviceAlerts.map(\.message) }
    @Published public private(set) var error: String?

    public var fetchedAt: Date? { departures?.fetchedAt }

    private var timers: [Timer] = []

    public init(autoRefresh: Bool = true) {
        guard autoRefresh else { return }
        start()
    }

    /// Starts polling (no-op if already running). Pair with `stop()` to pause it.
    public func start() {
        guard timers.isEmpty else { return }
        Task { await refresh() }
        Task { await refreshAlerts() }
        // The train feed updates roughly every 10–15 s; poll a bit faster so we
        // never lag the platform sign by more than one cycle.
        timers.append(Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        })
        // The 30-day alert history is ~400 KB and changes rarely.
        timers.append(Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.refreshAlerts() }
        })
    }

    public func stop() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }

    public func refresh() async {
        do {
            departures = try await FeedClient.departures()
            error = nil
        } catch {
            self.error = "OFFLINE · RETRYING"
        }
    }

    public func refreshAlerts() async {
        if let a = try? await FeedClient.serviceAlerts() {
            serviceAlerts = a
            alertsFetchedAt = Date()
        }
    }

    public func destinations(_ code: String) -> [Destination] {
        departures?.directions(code) ?? []
    }

    public func nextTrain(_ code: String) -> Message? {
        destinations(code).flatMap(\.messages).min { $0.seconds < $1.seconds }
    }

    public func tickerText(station: String) -> String {
        alerts.isEmpty
            ? "PATH  •  NO SERVICE ALERTS AT THIS TIME  •  \(stationName(station))"
            : alerts.joined(separator: "     •     ")
    }
}
