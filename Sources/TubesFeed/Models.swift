import Foundation

// MARK: - Feeds
// Both come from the Port Authority's own site: ridepath.json is the TrainDisplay
// data behind the platform signs / RidePATH app, alerts is the PATHAlert feed.

public let feedURL = URL(string: "https://www.panynj.gov/bin/portauthority/ridepath.json")!
// 30 days back: long-running incidents (elevator outages, multi-week advisories) stay
// "open" well past the 8 hours panynj.gov's own page asks for.
public let alertsURL = URL(string: "https://www.panynj.gov/bin/portauthority/alerts?agency=PATH&hours=720")!

public struct Feed: Decodable {
    public let results: [StationResult]
}

public struct StationResult: Decodable {
    public let consideredStation: String
    public let destinations: [Destination]
}

/// One direction at a station: label is "ToNY" or "ToNJ".
public struct Destination: Codable, Hashable, Sendable {
    public let label: String
    public let messages: [Message]

    public init(label: String, messages: [Message]) {
        self.label = label
        self.messages = messages
    }
}

public struct Message: Codable, Hashable, Identifiable, Sendable {
    public let target: String
    public let secondsToArrival: String
    public let arrivalTimeMessage: String
    public let lineColor: String
    public let headSign: String
    public let lastUpdated: String

    public init(target: String, secondsToArrival: String, arrivalTimeMessage: String,
                lineColor: String, headSign: String, lastUpdated: String) {
        self.target = target
        self.secondsToArrival = secondsToArrival
        self.arrivalTimeMessage = arrivalTimeMessage
        self.lineColor = lineColor
        self.headSign = headSign
        self.lastUpdated = lastUpdated
    }

    public var id: String { target + headSign + secondsToArrival }
    public var seconds: Int { Int(secondsToArrival) ?? 0 }
    public var hexColors: [String] {
        lineColor.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
    }

    /// Predicted arrival: the feed's own timestamp plus the countdown, so it doesn't drift
    /// with how long our request took. Falls back to `fallback` if the timestamp is odd.
    public func arrival(fallback: Date) -> Date {
        (parseFeedTimestamp(lastUpdated) ?? fallback).addingTimeInterval(TimeInterval(seconds))
    }
}

/// "2026-10-16T00:25:22.143984-04:00" -> Date (fractional seconds dropped).
func parseFeedTimestamp(_ s: String) -> Date? {
    guard s.count >= 25 else { return nil }
    let base = s.prefix(19)                       // 2026-10-16T00:25:22
    let zone = s.suffix(6)                        // -04:00
    guard zone.first == "-" || zone.first == "+" else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: String(base) + String(zone))
}

public struct Alert: Decodable {
    public let ebid: Int64?
    public let messageid: Int64?
    public let sentdate2: String?
    public let SentMessage: String?
    public let Subject: String?
    public let state: String?

    var sentMillis: Int64 {
        Int64(sentdate2?.filter(\.isNumber) ?? "") ?? 0
    }
}

/// An open PATHAlert incident, as shown on panynj.gov.
public struct ServiceAlert: Identifiable, Hashable, Sendable {
    public let id: String
    public let subject: String
    public let message: String
    public let sentAt: Date?

    /// Elevator / escalator outages, listed separately from train service changes.
    public var isAccessibility: Bool {
        let text = (subject + " " + message).lowercased()
        return text.contains("elevator") || text.contains("escalator")
    }

    /// Whether the alert names this station: its full name ("Journal Square") or its code
    /// on its own ("JSQ elevator"), but not a line name like "JSQ-33".
    public func mentions(_ station: Station) -> Bool {
        let text = (subject + " " + message).lowercased()
        if text.contains(station.name.lowercased()) { return true }
        let code = NSRegularExpression.escapedPattern(for: station.code.lowercased())
        return text.range(of: "(?<![-\\w])\(code)(?![-\\w])", options: .regularExpression) != nil
    }
}

/// Same rule as panynj.gov: one alert per Everbridge incident, latest message wins;
/// only incidents still open are shown, newest first.
public func openServiceAlerts(_ list: [Alert]) -> [ServiceAlert] {
    var latest: [String: Alert] = [:]
    for a in list {
        let key = a.ebid.map { "eb\($0)" } ?? "m\(a.messageid ?? 0)"
        if let cur = latest[key], cur.sentMillis > a.sentMillis { continue }
        latest[key] = a
    }
    return latest
        .filter { $0.value.state?.lowercased() == "open" }
        .sorted { $0.value.sentMillis > $1.value.sentMillis }
        .compactMap { key, a in
            guard let text = a.SentMessage ?? a.Subject else { return nil }
            return ServiceAlert(
                id: key,
                subject: (a.Subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                message: text.trimmingCharacters(in: .whitespacesAndNewlines),
                sentAt: a.sentMillis > 0 ? Date(timeIntervalSince1970: Double(a.sentMillis) / 1000) : nil)
        }
}

public func openAlertMessages(_ list: [Alert]) -> [String] {
    openServiceAlerts(list).map(\.message)
}

// MARK: - Stations

public struct Station: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public var id: String { code }
}

public let stations: [Station] = [
    .init(code: "NWK", name: "Newark", latitude: 40.7347, longitude: -74.1644),
    .init(code: "HAR", name: "Harrison", latitude: 40.7393, longitude: -74.1558),
    .init(code: "JSQ", name: "Journal Square", latitude: 40.7330, longitude: -74.0630),
    .init(code: "GRV", name: "Grove Street", latitude: 40.7196, longitude: -74.0430),
    .init(code: "EXP", name: "Exchange Place", latitude: 40.7163, longitude: -74.0329),
    .init(code: "NEW", name: "Newport", latitude: 40.7268, longitude: -74.0340),
    .init(code: "HOB", name: "Hoboken", latitude: 40.7353, longitude: -74.0291),
    .init(code: "WTC", name: "World Trade Center", latitude: 40.7126, longitude: -74.0099),
    .init(code: "CHR", name: "Christopher Street", latitude: 40.7329, longitude: -74.0071),
    .init(code: "09S", name: "9th Street", latitude: 40.7342, longitude: -73.9989),
    .init(code: "14S", name: "14th Street", latitude: 40.7374, longitude: -73.9969),
    .init(code: "23S", name: "23rd Street", latitude: 40.7429, longitude: -73.9929),
    .init(code: "33S", name: "33rd Street", latitude: 40.7491, longitude: -73.9882),
]

public func stationName(_ code: String) -> String {
    stations.first { $0.code == code }?.name ?? code
}

/// Nearest station by straight-line distance, with that distance in metres.
public func nearestStation(latitude: Double, longitude: Double) -> (station: Station, meters: Double) {
    func meters(_ s: Station) -> Double {
        let r = 6_371_000.0
        let dLat = (s.latitude - latitude) * .pi / 180
        let dLon = (s.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * .pi / 180) * cos(s.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
    let best = stations.min { meters($0) < meters($1) }!
    return (best, meters(best))
}

/// Directions in sign order: New York first.
public func sortedDirections(_ dests: [Destination]) -> [Destination] {
    dests.sorted { $0.label == "ToNY" && $1.label != "ToNY" }
}
