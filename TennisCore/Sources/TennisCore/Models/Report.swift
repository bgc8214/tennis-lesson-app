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
        /// 3번(원문/표시 분리): STT 오인식을 최소 교정한 정제본. 표시 전용이며
        /// 원문(quote)은 그대로 보존된다. 백엔드가 안 주면 nil → 원문으로 폴백.
        public let quoteDisplay: String?
        public let problem: String?
        public let fix: String?
        public let importance: String
        public let matchScore: Double?

        enum CodingKeys: String, CodingKey {
            case sec, type, category, label, quote, problem, fix, importance
            case quoteDisplay = "quote_display"
            case matchScore = "match_score"
        }

        // 소스(앱/백엔드)에 따라 type·importance 등이 빠질 수 있어 관대하게 디코딩한다.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sec = try c.decodeIfPresent(Int.self, forKey: .sec) ?? 0
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
            category = try c.decodeIfPresent(String.self, forKey: .category)
            label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
            quote = try c.decodeIfPresent(String.self, forKey: .quote)
            quoteDisplay = try c.decodeIfPresent(String.self, forKey: .quoteDisplay)
            problem = try c.decodeIfPresent(String.self, forKey: .problem)
            fix = try c.decodeIfPresent(String.self, forKey: .fix)
            importance = try c.decodeIfPresent(String.self, forKey: .importance) ?? "normal"
            matchScore = try c.decodeIfPresent(Double.self, forKey: .matchScore)
        }
    }

    public struct Scenario: Codable, Sendable, Hashable {
        public let condition: String
        public let action: String

        enum CodingKeys: String, CodingKey { case condition, action }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            condition = try c.decodeIfPresent(String.self, forKey: .condition) ?? ""
            action = try c.decodeIfPresent(String.self, forKey: .action) ?? ""
        }
    }

    public struct AiContextItem: Codable, Sendable, Identifiable, Hashable {
        public var id: String { title }
        public let title: String
        public let note: String

        enum CodingKeys: String, CodingKey { case title, note }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        }
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        card1Problem = try c.decodeIfPresent(String.self, forKey: .card1Problem)
        card1Evidence = try c.decodeIfPresent(String.self, forKey: .card1Evidence)
        card2Cueing = try c.decodeIfPresent(String.self, forKey: .card2Cueing)
        card2Evidence = try c.decodeIfPresent(String.self, forKey: .card2Evidence)
        card3Action = try c.decodeIfPresent(String.self, forKey: .card3Action)
        card3Evidence = try c.decodeIfPresent(String.self, forKey: .card3Evidence)
        fullSummary = try c.decodeIfPresent(String.self, forKey: .fullSummary)
        // 배열 필드는 소스(앱 자체 파이프라인 vs 백엔드)에 따라 없을 수 있으므로
        // 없으면 빈 배열로 관대하게 디코딩한다(백엔드 리포트엔 lesson_type이 없음).
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        lessonType = try c.decodeIfPresent([String].self, forKey: .lessonType) ?? []
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
        scenarios = try c.decodeIfPresent([Scenario].self, forKey: .scenarios) ?? []
        timestamps = try c.decodeIfPresent([TimestampItem].self, forKey: .timestamps) ?? []
        geminiModel = try c.decodeIfPresent(String.self, forKey: .geminiModel)
        transcriptText = try c.decodeIfPresent(String.self, forKey: .transcriptText)
        aiContext = try c.decodeIfPresent([AiContextItem].self, forKey: .aiContext) ?? []
        transcriptQuality = try c.decodeIfPresent(String.self, forKey: .transcriptQuality)
    }

    public static func decode(fromJSON json: String) throws -> Report {
        try JSONDecoder().decode(Report.self, from: Data(json.utf8))
    }
}
