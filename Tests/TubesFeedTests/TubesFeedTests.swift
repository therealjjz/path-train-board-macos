import Foundation
import Testing
@testable import TubesFeed

private func msg(_ target: String, _ head: String, _ secs: Int, color: String = "D93A30") -> Message {
    Message(target: target, secondsToArrival: String(secs), arrivalTimeMessage: "\(secs / 60) min",
            lineColor: color, headSign: head, lastUpdated: "")
}

@Test func parsesFeedTimestamp() {
    let d = parseFeedTimestamp("2026-10-16T00:25:22.143984-04:00")
    #expect(d == ISO8601DateFormatter().date(from: "2026-10-16T04:25:22Z"))
    #expect(parseFeedTimestamp("") == nil)
}

@Test func arrivalUsesFeedTimestamp() {
    let m = Message(target: "WTC", secondsToArrival: "120", arrivalTimeMessage: "2 min",
                    lineColor: "D93A30", headSign: "World Trade Center",
                    lastUpdated: "2026-10-16T00:25:22.1-04:00")
    #expect(m.arrival(fallback: .distantPast) == ISO8601DateFormatter().date(from: "2026-10-16T04:27:22Z"))
}

@Test func splitLineColours() {
    #expect(msg("33S", "33rd Street via Hoboken", 60, color: "4D92FB,FF9900").hexColors == ["4D92FB", "FF9900"])
}

@Test func nearestStationFromHobokenTerminal() {
    let (s, m) = nearestStation(latitude: 40.7355, longitude: -74.0287)
    #expect(s.code == "HOB")
    #expect(m < 100)
}
