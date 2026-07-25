import Foundation

/// Python dict의 느슨한 타입을 흉내 내기 위한 최소 JSON 값 타입.
/// Gemini 리포트 dict는 임의 추가 키를 가질 수 있고(`verified = dict(item)`처럼
/// 원본을 그대로 복사해 일부만 덮어씀), Swift의 정적 Codable 모델로는 그 유연성을
/// 표현하기 어려워 이 타입으로 원본 파이썬 dict 처리 방식을 그대로 재현한다.
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case double(Double)
    case int(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public var stringValue: String? {
        if case let .string(v) = self { return v }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        case .string(let v): return Double(v)
        default: return nil
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case let .object(v) = self { return v }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(v) = self { return v }
        return nil
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
