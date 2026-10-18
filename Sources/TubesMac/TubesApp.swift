import SwiftUI
import AppKit
import ServiceManagement
import TubesFeed
import TubesUI

struct BoardView: View {
    @ObservedObject var store: BoardStore
    @AppStorage("station") private var station = "GRV"
    @AppStorage("pinned") private var pinned = true
    var inWindow = true

    private let pitch: CGFloat = 2.34

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

            LEDModule { Ticker(text: store.tickerText(station: station), pitch: pitch) }

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

func boardWindow() -> NSWindow? {
    NSApp.windows.first { $0.identifier?.rawValue.contains("board") == true }
}

/// Settings shared by the menu bar item and the board's right-click menu.
struct SettingsMenu: View {
    @ObservedObject var store: BoardStore
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
    @ObservedObject var store: BoardStore
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
                        LineDot(hex: first.hexColors)
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

/// `Tubes --render-assets <dir>` writes the README screenshots and the app icon, then exits.
@MainActor
func renderAssetsIfRequested() {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--render-assets"), i + 1 < args.count else { return }
    let dir = URL(fileURLWithPath: args[i + 1])
    let store = BoardStore(autoRefresh: false)

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

    private var ledFrame: (LEDFrame, [Color]) {
        var f = LEDFrame(cols: 31, rows: 19)
        f.text("TUBES", x: 1, y: 2, color: 1)
        for (n, c) in [2, 3, 4, 5].enumerated() { f.lineMarker(x: 2 + n * 7 + 1, y: 11, colors: [UInt8(c)]) }
        return (f, [.clear, ledAmber, Color(hex: "D93A30"), Color(hex: "4D92FB"), Color(hex: "FF9900"), Color(hex: "65C100")])
    }

    var body: some View {
        let (f, palette) = ledFrame
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
    @StateObject private var store = BoardStore()

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
