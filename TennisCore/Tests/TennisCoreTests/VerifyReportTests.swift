import Foundation
import Testing
@testable import TennisCore

private struct VerifyFixture: Decodable {
    let result: [String: JSONValue]
    let stats: FixtureStats

    struct FixtureStats: Decodable {
        let matchThreshold: Double
        let timestampsTotal: Int
        let timestampsVerified: Int
        let timestampsDropped: Int
        let cardsDropped: [String]

        enum CodingKeys: String, CodingKey {
            case matchThreshold = "match_threshold"
            case timestampsTotal = "timestamps_total"
            case timestampsVerified = "timestamps_verified"
            case timestampsDropped = "timestamps_dropped"
            case cardsDropped = "cards_dropped"
        }
    }
}

private func loadVerifyFixture() throws -> VerifyFixture {
    let url = Bundle.module.url(forResource: "verify_report_case", withExtension: "json", subdirectory: "Fixtures")!
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(VerifyFixture.self, from: data)
}

@Test func verifyReportMatchesServer() throws {
    let fixture = try loadVerifyFixture()

    let segments: [SttSegment] = [
        SttSegment(start: 10.0, end: 14.0, text: "라켓을 뒤로 빼고 준비 자세를 잡으세요"),
        SttSegment(start: 14.0, end: 18.0, text: "그리고 스윙을 시작할 때는 어깨부터 돌려야 합니다"),
        SttSegment(start: 18.0, end: 22.0, text: "임팩트 순간에 팔을 쭉 뻗어주세요"),
        SttSegment(start: 30.0, end: 34.0, text: "백핸드는 두 손으로 치는 게 안정적이에요"),
        SttSegment(start: 34.0, end: 38.0, text: "발리는 짧게 끊어 치는 느낌으로"),
    ]

    let parsed: [String: JSONValue] = [
        "card1_problem": .string("라켓 준비 자세가 늦습니다"),
        "card1_evidence": .string("라켓을 뒤로 빼고 준비 자세를 잡으세요"),
        "card2_cueing": .string("어깨부터 돌리라는 큐잉을 받았습니다"),
        "card2_evidence": .string("완전히 지어낸 문장이라 전사에 없음"),
        "card3_action": .string(""),
        "card3_evidence": .string(""),
        "timestamps": .array([
            .object(["sec": .int(11), "quote": .string("라켓을 뒤로 빼고 준비 자세를 잡으세요"), "note": .string("패스스루필드")]),
            .object(["sec": .int(35), "quote": .string("발리는 짧게 끊어 치는 느낌으로")]),
            .object(["sec": .int(100), "quote": .string("전사에 전혀 없는 지어낸 인용문입니다")]),
            .object(["sec": .int(15), "quote": .string("임팩트 순간에 팔을 쭉 뻗어주세요")]),
        ]),
    ]

    let (result, stats) = verifyReport(parsed, segments: segments)

    #expect(stats.timestampsTotal == fixture.stats.timestampsTotal)
    #expect(stats.timestampsVerified == fixture.stats.timestampsVerified)
    #expect(stats.timestampsDropped == fixture.stats.timestampsDropped)
    #expect(Set(stats.cardsDropped) == Set(fixture.stats.cardsDropped))

    #expect(result["card2_cueing"] == .null)
    #expect(result["card1_problem"]?.stringValue == fixture.result["card1_problem"]?.stringValue)

    let resultTimestamps = result["timestamps"]?.arrayValue ?? []
    let expectedTimestamps = fixture.result["timestamps"]?.arrayValue ?? []
    #expect(resultTimestamps.count == expectedTimestamps.count)

    let resultSecs = resultTimestamps.map { $0.objectValue?["sec"]?.doubleValue ?? -1 }
    let expectedSecs = expectedTimestamps.map { $0.objectValue?["sec"]?.doubleValue ?? -1 }
    #expect(resultSecs == expectedSecs, "sec 재계산·정렬이 서버와 다름")

    // passthrough 필드(note)가 그대로 보존되는지
    let firstResult = resultTimestamps.first?.objectValue
    #expect(firstResult?["note"]?.stringValue == "패스스루필드")
}
