import Foundation
import Testing
@testable import TennisCore

private struct FixtureCase: Decodable {
    let label: String
    let aNorm: String
    let bNorm: String
    let ratio: Double
    let quickRatio: Double

    enum CodingKeys: String, CodingKey {
        case label
        case aNorm = "a_norm"
        case bNorm = "b_norm"
        case ratio
        case quickRatio = "quick_ratio"
    }
}

private func loadFixtures() throws -> [FixtureCase] {
    let url = Bundle.module.url(forResource: "sequence_matcher_cases", withExtension: "json", subdirectory: "Fixtures")!
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([FixtureCase].self, from: data)
}

@Test func sequenceMatcherMatchesPythonDifflib() throws {
    let cases = try loadFixtures()
    #expect(cases.count > 0)

    for c in cases {
        var matcher = SequenceMatcher(c.aNorm, c.bNorm)
        let ratio = matcher.ratio()
        let quickRatio = matcher.quickRatio()

        #expect(abs(ratio - c.ratio) < 1e-9, "\(c.label): ratio \(ratio) != python \(c.ratio)")
        #expect(abs(quickRatio - c.quickRatio) < 1e-9, "\(c.label): quick_ratio \(quickRatio) != python \(c.quickRatio)")
    }
}
