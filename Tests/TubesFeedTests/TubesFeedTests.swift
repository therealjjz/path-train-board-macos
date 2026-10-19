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

@Test func openAlertsKeepLatestOpenMessagePerIncident() throws {
    let json = """
    [{"ebid":1,"messageid":10,"sentdate2":"/Date(1000)/","Subject":"JSQ elevator out","SentMessage":"old","state":"Open"},
     {"ebid":1,"messageid":11,"sentdate2":"/Date(2000)/","Subject":"JSQ elevator out","SentMessage":"JSQ elevator between mezzanine and tracks is out of service","state":"Open"},
     {"ebid":2,"messageid":12,"sentdate2":"/Date(3000)/","Subject":"Delays","SentMessage":"resolved","state":"Closed"},
     {"ebid":3,"messageid":13,"sentdate2":"/Date(4000)/","Subject":"Hoboken advisory","SentMessage":"Travel advisory at Hoboken","state":"Open"}]
    """
    let alerts = openServiceAlerts(try JSONDecoder().decode([Alert].self, from: Data(json.utf8)))
    #expect(alerts.map(\.subject) == ["Hoboken advisory", "JSQ elevator out"])
    #expect(alerts[1].message.hasPrefix("JSQ elevator between"))
    #expect(alerts[1].isAccessibility && !alerts[0].isAccessibility)
    let jsq = stations.first { $0.code == "JSQ" }!, hob = stations.first { $0.code == "HOB" }!
    #expect(alerts[1].mentions(jsq) && !alerts[1].mentions(hob))
    #expect(alerts[0].mentions(hob))
}

@Test func lineNamesAreNotStationMentions() {
    let jsq = stations.first { $0.code == "JSQ" }!
    let weekend = ServiceAlert(id: "1", subject: "Planned Weekend Service", message: "NWK-WTC & HOB-WTC 20m; JSQ-33 & HOB-33 10m.", sentAt: nil)
    let elevator = ServiceAlert(id: "2", subject: "JSQ elevator out of service", message: "", sentAt: nil)
    #expect(!weekend.mentions(jsq))
    #expect(elevator.mentions(jsq))
}
