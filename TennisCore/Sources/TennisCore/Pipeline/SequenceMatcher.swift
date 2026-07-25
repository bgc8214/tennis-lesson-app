import Foundation

/// Python `difflib.SequenceMatcher(None, a, b)`의 Swift 포팅.
///
/// 서버 파이프라인(stt_filters.py/verification.py)이 `SequenceMatcher.ratio()`/
/// `.quick_ratio()`를 인용 검증 임계값(0.75) 판정에 그대로 쓰므로, Ratcliff-Obershelp
/// 알고리즘과 **autojunk 휴리스틱까지** 동일하게 재현해야 한다 — 대충 유사한 구현으로
/// 대체하면 임계값 경계에서 verified/dropped 판정이 서버와 달라진다(20문서 4절 경고).
/// `isjunk` 콜백은 서버가 항상 `None`으로 호출하므로 이식하지 않았다.
struct SequenceMatcher {
    private let a: [Character]
    private let b: [Character]
    /// element -> b에서의 등장 인덱스 목록. autojunk로 걸러진 "인기" 원소는 제외됨.
    private let b2j: [Character: [Int]]
    private let bJunk: Set<Character> = []
    private var matchingBlocksCache: [(i: Int, j: Int, size: Int)]?

    init(a: [Character], b: [Character], autojunk: Bool = true) {
        self.a = a
        self.b = b

        var rawB2j: [Character: [Int]] = [:]
        rawB2j.reserveCapacity(b.count)
        for (i, elt) in b.enumerated() {
            rawB2j[elt, default: []].append(i)
        }

        if autojunk && b.count >= 200 {
            let ntest = b.count / 100 + 1
            for (elt, idxs) in rawB2j where idxs.count > ntest {
                rawB2j.removeValue(forKey: elt)
            }
        }

        self.b2j = rawB2j
    }

    init(_ a: String, _ b: String) {
        self.init(a: Array(a), b: Array(b))
    }

    private func findLongestMatch(alo: Int, ahi: Int, blo: Int, bhi: Int) -> (i: Int, j: Int, size: Int) {
        var besti = alo, bestj = blo, bestsize = 0
        var j2len: [Int: Int] = [:]

        for i in alo..<ahi {
            var newj2len: [Int: Int] = [:]
            if let indices = b2j[a[i]] {
                for j in indices {
                    if j < blo { continue }
                    if j >= bhi { break }
                    let k = (j2len[j - 1] ?? 0) + 1
                    newj2len[j] = k
                    if k > bestsize {
                        besti = i - k + 1
                        bestj = j - k + 1
                        bestsize = k
                    }
                }
            }
            j2len = newj2len
        }

        while besti > alo, bestj > blo,
              !bJunk.contains(b[bestj - 1]),
              a[besti - 1] == b[bestj - 1] {
            besti -= 1; bestj -= 1; bestsize += 1
        }
        while besti + bestsize < ahi, bestj + bestsize < bhi,
              !bJunk.contains(b[bestj + bestsize]),
              a[besti + bestsize] == b[bestj + bestsize] {
            bestsize += 1
        }
        while besti > alo, bestj > blo,
              bJunk.contains(b[bestj - 1]),
              a[besti - 1] == b[bestj - 1] {
            besti -= 1; bestj -= 1; bestsize += 1
        }
        while besti + bestsize < ahi, bestj + bestsize < bhi,
              bJunk.contains(b[bestj + bestsize]),
              a[besti + bestsize] == b[bestj + bestsize] {
            bestsize += 1
        }

        return (besti, bestj, bestsize)
    }

    private mutating func matchingBlocks() -> [(i: Int, j: Int, size: Int)] {
        if let cached = matchingBlocksCache { return cached }

        let la = a.count, lb = b.count
        var queue: [(Int, Int, Int, Int)] = [(0, la, 0, lb)]
        var raw: [(i: Int, j: Int, size: Int)] = []

        while let (alo, ahi, blo, bhi) = queue.popLast() {
            let match = findLongestMatch(alo: alo, ahi: ahi, blo: blo, bhi: bhi)
            if match.size > 0 {
                raw.append(match)
                if alo < match.i && blo < match.j {
                    queue.append((alo, match.i, blo, match.j))
                }
                if match.i + match.size < ahi && match.j + match.size < bhi {
                    queue.append((match.i + match.size, ahi, match.j + match.size, bhi))
                }
            }
        }
        raw.sort { $0.i != $1.i ? $0.i < $1.i : $0.j < $1.j }

        var nonAdjacent: [(i: Int, j: Int, size: Int)] = []
        var i1 = 0, j1 = 0, k1 = 0
        for (i2, j2, k2) in raw {
            if i1 + k1 == i2 && j1 + k1 == j2 {
                k1 += k2
            } else {
                if k1 > 0 { nonAdjacent.append((i1, j1, k1)) }
                i1 = i2; j1 = j2; k1 = k2
            }
        }
        if k1 > 0 { nonAdjacent.append((i1, j1, k1)) }
        nonAdjacent.append((la, lb, 0))

        matchingBlocksCache = nonAdjacent
        return nonAdjacent
    }

    /// `SequenceMatcher.ratio()` — 2*M / T (M=매칭 문자 수, T=a+b 길이).
    mutating func ratio() -> Double {
        let matches = matchingBlocks().reduce(0) { $0 + $1.size }
        return Self.calculateRatio(matches: matches, length: a.count + b.count)
    }

    /// `SequenceMatcher.quick_ratio()` — 원소 빈도수만으로 낸 ratio 상한. b2j/autojunk와
    /// 무관하게 self.b 전체 빈도를 다시 센다(Python 원본과 동일하게 자체 카운트 사용).
    func quickRatio() -> Double {
        var fullBCount: [Character: Int] = [:]
        for elt in b { fullBCount[elt, default: 0] += 1 }

        var avail: [Character: Int] = [:]
        var matches = 0
        for elt in a {
            let numb = avail[elt] ?? fullBCount[elt, default: 0]
            avail[elt] = numb - 1
            if numb > 0 { matches += 1 }
        }
        return Self.calculateRatio(matches: matches, length: a.count + b.count)
    }

    private static func calculateRatio(matches: Int, length: Int) -> Double {
        guard length > 0 else { return 1.0 }
        return 2.0 * Double(matches) / Double(length)
    }
}
