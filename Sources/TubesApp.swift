import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Feeds
// Both come from the Port Authority's own site: ridepath.json is the TrainDisplay
// data behind the platform signs / RidePATH app, alerts is the PATHAlert feed.

let feedURL = URL(string: "https://www.panynj.gov/bin/portauthority/ridepath.json")!
let alertsURL = URL(string: "https://www.panynj.gov/bin/portauthority/alerts?agency=PATH&hours=8")!

struct Feed: Decodable { let results: [StationResult] }

struct StationResult: Decodable {
    let consideredStation: String
    let destinations: [Destination]
}

struct Destination: Decodable {
    let label: String
    let messages: [Message]
}

struct Message: Decodable, Identifiable {
    let target: String
    let secondsToArrival: String
    let arrivalTimeMessage: String
    let lineColor: String
    let headSign: String
    let lastUpdated: String

    var id: String { target + headSign + secondsToArrival }
    var seconds: Int { Int(secondsToArrival) ?? 0 }
    var hexColors: [String] { lineColor.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() } }
}

struct Alert: Decodable {
    let ebid: Int64?
    let messageid: Int64?
    let sentdate2: String?
    let SentMessage: String?
    let Subject: String?
    let state: String?

    var sentMillis: Int64 {
        Int64(sentdate2?.filter(\.isNumber) ?? "") ?? 0
    }
}

struct Station: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

let stations: [Station] = [
    .init(code: "NWK", name: "Newark"),
    .init(code: "HAR", name: "Harrison"),
    .init(code: "JSQ", name: "Journal Square"),
    .init(code: "GRV", name: "Grove Street"),
    .init(code: "EXP", name: "Exchange Place"),
    .init(code: "NEW", name: "Newport"),
    .init(code: "HOB", name: "Hoboken"),
    .init(code: "WTC", name: "World Trade Center"),
    .init(code: "CHR", name: "Christopher Street"),
    .init(code: "09S", name: "9th Street"),
    .init(code: "14S", name: "14th Street"),
    .init(code: "23S", name: "23rd Street"),
    .init(code: "33S", name: "33rd Street"),
]

func stationName(_ code: String) -> String {
    stations.first { $0.code == code }?.name ?? code
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: .whitespaces), radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var feed: [String: [Destination]] = [:]
    @Published var alerts: [String] = []
    @Published var fetchedAt: Date?
    @Published var error: String?

    private var timers: [Timer] = []

    init() {
        Task { await refresh() }
        Task { await refreshAlerts() }
        // The train feed updates roughly every 10–15 s; poll a bit faster so we
        // never lag the platform sign by more than one cycle.
        timers.append(Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refreshAlerts() }
        })
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await URLSession.shared.data(for: req).0
    }

    func refresh() async {
        do {
            let decoded = try JSONDecoder().decode(Feed.self, from: try await get(feedURL))
            feed = Dictionary(decoded.results.map { ($0.consideredStation, $0.destinations) },
                              uniquingKeysWith: { a, _ in a })
            fetchedAt = Date()
            error = nil
        } catch {
            self.error = "连接失败，正在重试…"
        }
    }

    func refreshAlerts() async {
        guard let list = try? JSONDecoder().decode([Alert].self, from: try await get(alertsURL)) else { return }
        // Same rule as panynj.gov: one alert per Everbridge incident, latest message wins.
        var latest: [String: Alert] = [:]
        for a in list {
            let key = a.ebid.map { "eb\($0)" } ?? "m\(a.messageid ?? 0)"
            if let cur = latest[key], cur.sentMillis > a.sentMillis { continue }
            latest[key] = a
        }
        alerts = latest.values
            .filter { $0.state?.lowercased() == "open" }
            .sorted { $0.sentMillis > $1.sentMillis }
            .compactMap { $0.SentMessage ?? $0.Subject }
    }

    func destinations(_ code: String) -> [Destination] {
        (feed[code] ?? []).sorted { $0.label == "ToNY" && $1.label != "ToNY" }
    }

    func nextTrain(_ code: String) -> Message? {
        destinations(code).flatMap(\.messages).min { $0.seconds < $1.seconds }
    }
}

// MARK: - LED board

let boardCols = 210
let maxTrainsPerDirection = 3

/// Palette indices: 1 = amber, 2 = dim amber, 3+ = line colours.
struct BoardFrame {
    var frame: LEDFrame
    var palette: [Color]
}

func makeBoard(station: String, dests: [Destination], loaded: Bool, now: Date) -> BoardFrame {
    var palette: [Color] = [.clear, ledAmber, ledAmber.opacity(0.55)]
    var lineIndex: [String: UInt8] = [:]
    func colorIndex(_ hex: String) -> UInt8 {
        if let i = lineIndex[hex] { return i }
        palette.append(Color(hex: hex))
        lineIndex[hex] = UInt8(palette.count - 1)
        return lineIndex[hex]!
    }

    let sections = dests.isEmpty ? [nil] : dests.map { Optional($0) }
    // Fixed size so the window doesn't jump between stations: header + two direction
    // blocks of (rule + gap 4, label 9, three trains 9 each). Unused rows stay dark.
    let rows = 7 + 2 * (13 + 9 * maxTrainsPerDirection)
    var f = LEDFrame(cols: boardCols, rows: rows)

    let clock = DateFormatter()
    clock.timeZone = TimeZone(identifier: "America/New_York")
    clock.dateFormat = "h:mm a"
    f.text(stationName(station), x: 0, y: 0, color: 1)
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
            f.lineMarker(x: 0, y: y, colors: m.hexColors.map(colorIndex))
            let time = m.arrivalTimeMessage
            let timeW = DotFont.width(time)
            var sign = m.headSign
            while DotFont.width(sign) > boardCols - 8 - timeW - 6 && !sign.isEmpty { sign.removeLast() }
            f.text(sign, x: 8, y: y, color: 1)
            f.text(time, x: boardCols, y: y, color: 1, rightAligned: true)
            y += 9
        }
    }
    return BoardFrame(frame: f, palette: palette)
}

struct Ticker: View {
    let text: String
    var pitch: CGFloat
    private let speed = 28.0   // LED columns per second

    var body: some View {
        let cols = DotFont.columns(text)
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let span = cols.count + boardCols
            let step = Int(ctx.date.timeIntervalSinceReferenceDate * speed) % max(1, span)
            var f = LEDFrame(cols: boardCols, rows: 7)
            f.blit(cols, x: boardCols - step, y: 0, color: 1)
            return LEDCanvas(frame: f, palette: [.clear, ledAmber], pitch: pitch)
        }
    }
}

struct BoardView: View {
    @ObservedObject var store: Store
    @AppStorage("station") private var station = "GRV"
    @AppStorage("pinned") private var pinned = true
    var inWindow = true

    private let pitch: CGFloat = 2.34

    private var tickerText: String {
        store.alerts.isEmpty
            ? "PATH  •  NO SERVICE ALERTS AT THIS TIME  •  \(stationName(station))"
            : store.alerts.joined(separator: "     •     ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                // Wide heavy italic, close to the PATH wordmark lettering.
                Text("PATH")
                    .font(.custom("AvenirNext-HeavyItalic", size: 14.5))
                    .kerning(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.07, green: 0.26, blue: 0.84)))
                Spacer()
                StatusLamp(store: store)
            }

            LEDModule { Ticker(text: tickerText, pitch: pitch) }

            LEDModule {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let b = makeBoard(station: station, dests: store.destinations(station),
                                      loaded: store.fetchedAt != nil, now: ctx.date)
                    LEDCanvas(frame: b.frame, palette: b.palette, pitch: pitch)
                }
            }
        }
        .padding(12.5)
        .fixedSize()
        .background(Housing())
        .environment(\.colorScheme, .dark)
        .contextMenu { SettingsMenu(store: store) }
        .background { if inWindow { WindowPinner(pinned: pinned) } }
    }
}

/// Little indicator LED on the housing: green when synced, red when the feed is unreachable.
struct StatusLamp: View {
    @ObservedObject var store: Store
    var body: some View {
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
struct Housing: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
            Noise.image.resizable(resizingMode: .tile)
                .opacity(0.05)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            RoundedRectangle(cornerRadius: 10)
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

func boardWindow() -> NSWindow? {
    NSApp.windows.first { $0.identifier?.rawValue.contains("board") == true }
}

/// Settings shared by the menu bar item and the board's right-click menu.
struct SettingsMenu: View {
    @ObservedObject var store: Store
    @AppStorage("station") private var station = "GRV"
    @AppStorage("pinned") private var pinned = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Picker("Station", selection: $station) {
            ForEach(stations) { Text($0.name).tag($0.code) }
        }
        .pickerStyle(.inline)

        Divider()

        // Menu contents aren't re-evaluated on open, so decide at click time.
        Button("Show / Hide Board") {
            if let w = boardWindow(), w.isVisible {
                w.orderOut(nil)
            } else {
                openWindow(id: "board")
                NSApp.activate()
            }
        }
        .keyboardShortcut("b")
        Toggle("Keep Board on Top", isOn: $pinned)
        Toggle("Launch at Login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
        ))
        Button("Refresh Now") {
            Task { await store.refresh(); await store.refreshAlerts() }
        }
        .keyboardShortcut("r")

        Divider()

        Button("Quit Tubes") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Makes the board window frameless, transparent around the casing, and optionally floating.
struct WindowPinner: NSViewRepresentable {
    let pinned: Bool?
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ v: NSView, context: Context) {
        guard let pinned else { return }
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.level = pinned ? .floating : .normal
            w.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.isMovableByWindowBackground = true
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                w.standardWindowButton(b)?.isHidden = true
            }
        }
    }
}

/// Menu bar item. Plain menu bar text is forced monochrome, so the label is drawn as an
/// image to keep the line colours: [HAR]  ● WTC 37 52   ● NWK 15 45
struct MenuBarLabel: View {
    @ObservedObject var store: Store
    @AppStorage("station") private var station = "GRV"

    var body: some View {
        let content = MenuBarContent(station: station, dests: store.destinations(station), dark: menuBarIsDark())
        let r = ImageRenderer(content: content)
        r.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let img = r.nsImage {
            img.isTemplate = false
            return AnyView(Image(nsImage: img))
        }
        return AnyView(Text("PATH \(station)"))
    }
}

/// The status-bar window's appearance tracks the wallpaper, not the app's light/dark mode.
@MainActor
func menuBarIsDark() -> Bool {
    let w = NSApp.windows.first { String(describing: type(of: $0)).contains("StatusBar") }
    let a = w?.effectiveAppearance ?? NSApp.effectiveAppearance
    return a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

struct MenuBarContent: View {
    let station: String
    let dests: [Destination]
    let dark: Bool

    private var fg: Color { dark ? .white : .black }

    var body: some View {
        HStack(spacing: 9) {
            Text(station)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(fg)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(fg.opacity(0.85), lineWidth: 1.2))
            if dests.isEmpty {
                Text("—").font(.system(size: 12, weight: .medium)).foregroundStyle(fg.opacity(0.5))
            }
            ForEach(dests, id: \.label) { d in
                if let first = d.messages.first {
                    HStack(spacing: 4) {
                        MenuLineDot(hex: first.hexColors)
                        Text(first.target)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(fg.opacity(0.6))
                        Text(minutes(first))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(fg)
                        if let next = d.messages.dropFirst().first {
                            Text(minutes(next))
                                .font(.system(size: 11, weight: .regular).monospacedDigit())
                                .foregroundStyle(fg.opacity(0.45))
                        }
                    }
                }
            }
        }
        .fixedSize()
        .frame(height: 18)
    }

    /// "16 min" -> "16"; anything else (e.g. "Arriving") is shown as-is.
    private func minutes(_ m: Message) -> String {
        let s = m.arrivalTimeMessage
        return s.hasSuffix(" min") ? String(s.dropLast(4)) : s
    }
}

struct MenuLineDot: View {
    let hex: [String]
    var body: some View {
        let colors = hex.map(Color.init(hex:))
        ZStack {
            if colors.count > 1 {
                Circle().trim(from: 0, to: 0.5).fill(colors[0]).rotationEffect(.degrees(90))
                Circle().trim(from: 0.5, to: 1).fill(colors[1]).rotationEffect(.degrees(90))
            } else {
                Circle().fill(colors.first ?? .gray)
            }
        }
        .frame(width: 7, height: 7)
    }
}

/// `Tubes --render-assets <dir>` writes the README screenshots and the app icon, then exits.
@MainActor
func renderAssetsIfRequested() {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--render-assets"), i + 1 < args.count else { return }
    let dir = URL(fileURLWithPath: args[i + 1])
    let store = Store()

    func write<V: View>(_ view: V, _ name: String, scale: CGFloat = 2) {
        let r = ImageRenderer(content: view)
        r.scale = scale
        if let cg = r.cgImage,
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent(name))
        }
    }

    Task { @MainActor in
        await store.refresh()
        await store.refreshAlerts()
        let station = UserDefaults.standard.string(forKey: "station") ?? "GRV"
        write(BoardView(store: store, inWindow: false).padding(24), "board.png")
        write(HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { dark in
                MenuBarContent(station: station, dests: store.destinations(station), dark: dark)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(dark ? Color(white: 0.13) : Color(white: 0.94))
            }
        }, "menubar.png", scale: 3)
        write(AppIcon(), "icon.png", scale: 1)
        exit(0)
    }
    RunLoop.main.run()
}

/// 1024x1024 icon: a little metal LED sign reading TUBES above the four PATH line colours.
struct AppIcon: View {
    var body: some View {
        var f = LEDFrame(cols: 31, rows: 19)
        f.text("TUBES", x: 1, y: 2, color: 1)
        for (n, c) in [2, 3, 4, 5].enumerated() { f.lineMarker(x: 2 + n * 7 + 1, y: 11, colors: [UInt8(c)]) }
        let palette: [Color] = [.clear, ledAmber, Color(hex: "D93A30"), Color(hex: "4D92FB"),
                                Color(hex: "FF9900"), Color(hex: "65C100")]
        return ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.27), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 6))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.45), radius: 20, y: 12)
            LEDCanvas(frame: f, palette: palette, pitch: 22)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 26).fill(Color(red: 0.03, green: 0.025, blue: 0.02)))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(.black, lineWidth: 6))
            ForEach(0..<4, id: \.self) { k in
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                    .offset(x: k % 2 == 0 ? -350 : 350, y: k < 2 ? -350 : 350)
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

@main
struct TubesApp: App {
    @StateObject private var store = Store()

    init() { renderAssetsIfRequested() }

    var body: some Scene {
        Window("Tubes", id: "board") {
            BoardView(store: store)
                .containerBackground(.clear, for: .window)
        }
        .windowResizability(.contentSize)
        .windowStyle(.plain)
        .windowBackgroundDragBehavior(.enabled)

        MenuBarExtra {
            SettingsMenu(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.menu)
    }
}
