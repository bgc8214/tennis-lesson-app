import Foundation

/// `ReportBuilder.build()`가 만든 dict를 UI에서 쓰기 편하게 디코딩하는 뷰 모델.
/// 필드 이름은 서버 응답 dict(및 웹 프론트 `src/types/lesson.ts`)와 1:1.
public struct Report: Codable, Sendable {
    public struct TimestampItem: Codable, Sendable, Identifiable, Hashable {
        public var id: String { "\(sec)-\(label)" }
        public let sec: Int
        public let type: String
        public let category: String?
        public let label: String
        public let quote: String?
        public let problem: String?
        public let fix: String?
        public let importance: String
        public let matchScore: Double?

        enum CodingKeys: String, CodingKey {
            case sec, type, category, label, quote, problem, fix, importance
            case matchScore = "match_score"
        }
    }

    public struct Scenario: Codable, Sendable, Hashable {
        public let condition: String
        public let action: String
    }

    public struct AiContextItem: Codable, Sendable, Identifiable, Hashable {
        public var id: String { title }
        public let title: String
        public let note: String
    }

    public let card1Problem: String?
    public let card1Evidence: String?
    public let card2Cueing: String?
    public let card2Evidence: String?
    public let card3Action: String?
    public let card3Evidence: String?
    public let fullSummary: String?
    public let keywords: [String]
    public let lessonType: [String]
    public let steps: [String]
    public let scenarios: [Scenario]
    public let timestamps: [TimestampItem]
    public let geminiModel: String?
    public let transcriptText: String?
    public let aiContext: [AiContextItem]
    public let transcriptQuality: String?

    enum CodingKeys: String, CodingKey {
        case card1Problem = "card1_problem"
        case card1Evidence = "card1_evidence"
        case card2Cueing = "card2_cueing"
        case card2Evidence = "card2_evidence"
        case card3Action = "card3_action"
        case card3Evidence = "card3_evidence"
        case fullSummary = "full_summary"
        case keywords
        case lessonType = "lesson_type"
        case steps, scenarios, timestamps
        case geminiModel = "gemini_model"
        case transcriptText = "transcript_text"
        case aiContext = "ai_context"
        case transcriptQuality = "transcript_quality"
    }

    public static func decode(fromJSON json: String) throws -> Report {
        try JSONDecoder().decode(Report.self, from: Data(json.utf8))
    }
}
