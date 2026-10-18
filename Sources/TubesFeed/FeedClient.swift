import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One fetch of the departures feed, keyed by station code.
public struct Departures: Sendable {
    public let byStation: [String: [Destination]]
    public let fetchedAt: Date

    public init(byStation: [String: [Destination]], fetchedAt: Date) {
        self.byStation = byStation
        self.fetchedAt = fetchedAt
    }

    public func directions(_ station: String) -> [Destination] {
        sortedDirections(byStation[station] ?? [])
    }
}

public enum FeedClient {
    static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    public static func departures() async throws -> Departures {
        let feed = try JSONDecoder().decode(Feed.self, from: try await get(feedURL))
        return Departures(
            byStation: Dictionary(feed.results.map { ($0.consideredStation, $0.destinations) },
                                  uniquingKeysWith: { a, _ in a }),
            fetchedAt: Date())
    }

    public static func alerts() async throws -> [String] {
        openAlertMessages(try JSONDecoder().decode([Alert].self, from: try await get(alertsURL)))
    }
}
