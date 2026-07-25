import Foundation
import Testing
@testable import TennisCore

private struct FilterFixtureStats: Decodable {
    let total: Int
    let droppedNoSpeech: Int
    let droppedLogprob: Int
    let droppedCompression: Int
    let droppedRepeat: Int
    let droppedEmpty: Int
    let kept: Int

    enum CodingKeys: String, CodingKey {
        case total
        case droppedNoSpeech = "dropped_no_speech"
        case droppedLogprob = "dropped_logprob"
        case droppedCompression = "dropped_compression"
        case droppedRepeat = "dropped_repeat"
        case droppedEmpty = "dropped_empty"
        case kept
    }
}

private struct FilterFixtureCase: Decodable {
    let keptTexts: [String]
    let stats: FilterFixtureStats

    enum CodingKeys: String, CodingKey {
        case keptTexts = "kept_texts"
        case stats
    }
}

private func loadFixtures() throws -> [String: FilterFixtureCase] {
    let url = Bundle.module.url(forResource: "stt_filters_cases", withExtension: "json", subdirectory: "Fixtures")!
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([String: FilterFixtureCase].self, from: data)
}

private func seg(_ start: Double, _ end: Double, _ text: String, nsp: Double? = nil, alp: Double? = nil, cr: Double? = nil) -> SttSegment {
    SttSegment(start: start, end: end, text: text, noSpeechProb: nsp, avgLogprob: alp, compressionRatio: cr)
}

@Test func filterHallucinatedSegmentsMatchesServer() throws {
    let fixtures = try loadFixtures()

    let mixedThresholds: [SttSegment] = [
        seg(0.0, 2.0, "안녕하세요 코치님", nsp: 0.1, alp: -0.3, cr: 1.2),
        seg(2.0, 4.0, "", nsp: 0.1, alp: -0.3, cr: 1.2),
        seg(4.0, 6.0, "무음구간창작의심문장", nsp: 0.75, alp: -0.3, cr: 1.2),
        seg(6.0, 8.0, "저신뢰디코딩문장입니다", nsp: 0.1, alp: -1.5, cr: 1.2),
        seg(8.0, 10.0, "반복루프환청문장반복루프환청문장", nsp: 0.1, alp: -0.3, cr: 3.0),
        seg(10.0, 12.0, "라켓을 뒤로 빼세요", nsp: 0.1, alp: -0.3, cr: 1.1),
        seg(12.0, 14.0, "라켓을 뒤로 빼세요", nsp: 0.1, alp: -0.3, cr: 1.1),
        seg(14.0, 16.0, "라켓을 뒤로 빼셔요", nsp: 0.1, alp: -0.3, cr: 1.1),
        seg(16.0, 18.0, "포핸드 스트로크 연습하겠습니다", nsp: 0.1, alp: -0.3, cr: 1.1),
        seg(18.0, 20.0, "None 메타 세그먼트", nsp: nil, alp: nil, cr: nil),
    ]
    let boundaryExact: [SttSegment] = [
        seg(0.0, 1.0, "경계압박테스트문장", nsp: 0.6, alp: -1.0, cr: 2.4)
    ]
    let emptyList: [SttSegment] = []

    let scenarios: [(String, [SttSegment])] = [
        ("mixed_thresholds", mixedThresholds),
        ("boundary_exact", boundaryExact),
        ("empty_list", emptyList),
    ]

    for (name, segments) in scenarios {
        guard let expected = fixtures[name] else {
            Issue.record("missing fixture: \(name)")
            continue
        }
        let (kept, stats) = filterHallucinatedSegments(segments)

        #expect(kept.map(\.text) == expected.keptTexts, "\(name): kept texts mismatch")
        #expect(stats.total == expected.stats.total, "\(name): total")
        #expect(stats.droppedNoSpeech == expected.stats.droppedNoSpeech, "\(name): droppedNoSpeech")
        #expect(stats.droppedLogprob == expected.stats.droppedLogprob, "\(name): droppedLogprob")
        #expect(stats.droppedCompression == expected.stats.droppedCompression, "\(name): droppedCompression")
        #expect(stats.droppedRepeat == expected.stats.droppedRepeat, "\(name): droppedRepeat")
        #expect(stats.droppedEmpty == expected.stats.droppedEmpty, "\(name): droppedEmpty")
        #expect(stats.kept == expected.stats.kept, "\(name): kept count")
    }
}

@Test func normalizeTextStripsToKoreanAndAlnum() {
    #expect(normalizeText("안녕하세요!") == "안녕하세요")
    #expect(normalizeText("Hello World 123") == "helloworld123")
    #expect(normalizeText(nil) == "")
    #expect(normalizeText("   ") == "")
}
